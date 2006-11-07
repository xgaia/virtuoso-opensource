/*
 *  sqlbif2.c
 *
 *  $Id$
 *
 *  SQL Built In Functions. Part 2
 *  
 *  This file is part of the OpenLink Software Virtuoso Open-Source (VOS)
 *  project.
 *  
 *  Copyright (C) 1998-2006 OpenLink Software
 *  
 *  This project is free software; you can redistribute it and/or modify it
 *  under the terms of the GNU General Public License as published by the
 *  Free Software Foundation; only version 2 of the License, dated June 1991.
 *  
 *  This program is distributed in the hope that it will be useful, but
 *  WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 *  General Public License for more details.
 *  
 *  You should have received a copy of the GNU General Public License along
 *  with this program; if not, write to the Free Software Foundation, Inc.,
 *  51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
 *  
 *  
*/
#include "sqlnode.h"
#include "sqlfn.h"
#include "eqlcomp.h"
#include "lisprdr.h"
#include "sqlpar.h"
#include "sqlcmps.h"
#include "sqlintrp.h"
#include "sqlbif.h"
#include "arith.h"
#include "security.h"
#include "sqlpfn.h"
#include "http.h"
#include "libutil.h"
#include "sqloinv.h"

#ifdef HAVE_PWD_H
#include <pwd.h>
#endif
#ifdef HAVE_GRP_H
#include <grp.h>
#endif


static caddr_t
bif_ddl_read_constraints (caddr_t * qst, caddr_t * err_ret, state_slot_t ** args)
{
  caddr_t spec_tb_name = bif_string_or_null_arg (qst, args, 0, "__ddl_read_constraints");
  ddl_read_constraints (spec_tb_name, qst);
  return NULL;
}

static id_hash_t *name_to_pl_name;


void
pl_bif_name_define (const char *name)
{
  char buff[2 * MAX_NAME_LEN];
  caddr_t data;
  if (!name_to_pl_name)
    {
      name_to_pl_name = id_casemode_hash_create (101);
    }
  name = sqlp_box_id_upcase (name);
  if (strchr (name, NAME_SEPARATOR))
    strcpy_ck (buff, name);
  else
    snprintf (buff, sizeof (buff), "DB.DBA.%s", name);
  data = sym_string (buff);
  id_hash_set (name_to_pl_name, (char *) &name, (char *) &data);
}


caddr_t
find_pl_bif_name (caddr_t name)
{
  caddr_t *full = (caddr_t *) id_hash_get (name_to_pl_name, (caddr_t) &name);
  if (full)
    return *full;
  else if (case_mode == CM_MSSQL)
    {
      caddr_t name2 = sqlp_box_id_upcase (name);
      full = (caddr_t *) id_hash_get (name_to_pl_name, (caddr_t) &name2);
      dk_free_box (name2);
      if (full)
	return *full;
    }
  return name;
}

int lockdown_mode = 0;

typedef struct co_req_2_s {
   semaphore_t *sem;
   dk_set_t *set;
} co_req_2_t;

static void
collect_listeners (co_req_2_t *req)
{
  dk_set_t peers = PrpcListPeers ();
  DO_SET (dk_session_t *, peer, &peers)
    {
      if (SESSTAT_ISSET (peer->dks_session, SST_LISTENING) &&
	  !PrpcIsListen (peer))
	{
	  remove_from_served_sessions (peer);
	  dk_set_push (req->set, peer);
	}
    }
  END_DO_SET ();
  if (req->sem)
    semaphore_leave (req->sem);
}

static void
restore_listeners (co_req_2_t *req)
{
  DO_SET (dk_session_t *, listener, req->set)
    {
      add_to_served_sessions (listener);
    }
  END_DO_SET ();
  dk_set_free (*req->set);
  *req->set = NULL;
  if (req->sem)
    semaphore_leave (req->sem);
}


int
dks_is_localhost (dk_session_t *ses)
{
  if (ses->dks_session->ses_class == SESCLASS_UNIX)
    return 1;
  else if (ses->dks_session->ses_class == SESCLASS_TCPIP)
    {
      char buf[150];
      if (!tcpses_getsockname (ses->dks_session, buf, sizeof (buf)))
	{
	  if (!strncmp (buf, "127.0.0.1", 9))
	    return 1;
	}
    }
  return 0;
}


static caddr_t
bif_sys_lockdown (caddr_t * qst, caddr_t * err_ret, state_slot_t ** args)
{
  ptrlong lockdown = bif_long_arg (qst, args, 0, "sys_lockdown");
  query_instance_t *qi = (query_instance_t *) qst;
  dk_set_t clients;
  static dk_set_t listeners = NULL;
  co_req_2_t req;
  ptrlong disconnect_mode = 0;
  static ptrlong last_disconnect_mode = 0;
  long res = 0;

  sec_check_dba (qi, "sys_lockdown");

  req.sem = THREAD_CURRENT_THREAD->thr_sem;
  req.set = &listeners;
  if (BOX_ELEMENTS (args) > 1)
    disconnect_mode = bif_long_arg (qst, args, 1, "sys_lockdown");

  if (lockdown && !lockdown_mode)
    {
      dk_session_t *this_client_ses = IMMEDIATE_CLIENT;
      char buffer[50];

      if (!qi->qi_client->cli_ws)
	tcpses_print_client_ip (qi->qi_client->cli_session->dks_session, buffer, sizeof (buffer));
      else
	strncpy (buffer, qi->qi_client->cli_ws->ws_client_ip, sizeof (buffer));
      buffer[sizeof (buffer) - 1] = 0;

      if (!dks_is_localhost (this_client_ses))
	this_client_ses = NULL;

      logmsg (LOG_EMERG, NULL, 0, 1,
	  "Security lockdown mode ON (listeners %s) via sys_lockdown() called by %s (IP:%s)",
	  disconnect_mode ? "OFF" : "UNSERVED",
	  qi->qi_client->cli_user ? qi->qi_client->cli_user->usr_name : "<internal>",
	  buffer);
      lockdown_mode = 1;
#ifndef NDEBUG
      if (listeners)
        GPF_T1 ("listeners already there on locking the system down");
#endif
      PrpcSelfSignal ((self_signal_func) collect_listeners, (caddr_t) &req);
      semaphore_enter (req.sem);

      mutex_enter (thread_mtx);
      clients = srv_get_logons ();
      DO_SET (dk_session_t *, ses, &clients)
	{
	  if (ses != this_client_ses)
	    {
	      client_connection_t *cli = DKS_DB_DATA (ses);
	      if (cli)
		{
		  cli->cli_terminate_requested = 1;
		  ses->dks_to_close = 1;
		}
	    }
	}
      END_DO_SET ();
      mutex_leave (thread_mtx);
      last_disconnect_mode = disconnect_mode;
      if (disconnect_mode)
	{
	  DO_SET (dk_session_t *, ses, &listeners)
	    {
	      session_disconnect (ses->dks_session);
	    }
	  END_DO_SET ();
	}
      res = 1;
    }
  else if (!lockdown && lockdown_mode)
    {
      if (last_disconnect_mode)
	{
	  DO_SET (dk_session_t *, ses, &listeners)
	    {
	      without_scheduling_tic ();
	      session_listen (ses->dks_session);
	      without_scheduling_tic ();
	    }
	  END_DO_SET ();
	}
      lockdown_mode = 0;
      PrpcSelfSignal ((self_signal_func) restore_listeners, (caddr_t) &req);
      semaphore_enter (req.sem);
      log_info ("Security lockdown mode ended via sys_lockdown()");
      res = 2;
    }
  return box_num (res);
}


int
tcpses_check_disk_error (dk_session_t *ses, caddr_t *qst, int throw_error)
{
  query_instance_t *qi = (query_instance_t *) qst;

  if (!ses || !ses->dks_session || !ses->dks_session->ses_class != SESCLASS_STRING
      || !ses->dks_session->ses_file->ses_max_blocks_init)
    return 0;

  if (SESSTAT_ISSET (ses->dks_session, SST_DISK_ERROR))
    {
      if (qst)
	{
	  qi->qi_trx->lt_status = LT_BLOWN_OFF;
	  qi->qi_trx->lt_error = LTE_NO_DISK;
	}
      if (throw_error)
	{
	  sqlr_new_error ("42000", "SR452", "Error in accessing temp file");
	}
      return 1;
    }
  else
    return 0;
}


caddr_t
bif_session_arg (caddr_t * qst, state_slot_t ** args, int nth, char *func)
{
  caddr_t arg = bif_arg (qst, args, nth, func);
  dtp_t dtp = DV_TYPE_OF (arg);
  if (dtp != DV_STRING_SESSION && dtp != DV_CONNECTION)
    sqlr_new_error ("22023", "SR002",
	"Function %s needs a string output or a session as argument %d, not an arg of type %s (%d)",
	func, nth + 1, dv_type_title (dtp), dtp);
  return arg;
}


static caddr_t
bif_blob_handle_from_session (caddr_t * qst, caddr_t * err_ret, state_slot_t ** args)
{
  caddr_t ses = bif_session_arg (qst, args, 0, "__blob_handle_from_session");
  blob_handle_t *bh;
  caddr_t dummy_null;

  if (!ssl_is_settable (args[0]))
    sqlr_new_error ("22023", "SR453", "__blob_handle_from_session argument 1 must be IN/OUT");

  bh = bh_alloc (DV_BLOB_HANDLE_DTP_FOR_BLOB_DTP (DV_BLOB_BIN));
  bh->bh_ask_from_client = 3;
  bh->bh_source_session = ses;
  dummy_null = NEW_DB_NULL;
  qst_swap (qst, args[0], &dummy_null);

  return (caddr_t) bh;
}

bif_type_t bt_blob_handle = {NULL, DV_BLOB_HANDLE, 0, 0};


static caddr_t
bif_os_chmod (caddr_t * qst, caddr_t * err_ret, state_slot_t ** args)
{
  caddr_t fname = bif_string_arg (qst, args, 0, "os_chmod");
  long mod  = (long) bif_long_arg (qst, args, 1, "os_chmod");
  char *fname_cvt = NULL;
  int is_allocated = 0;
  caddr_t res;

#if defined (HAVE_CHMOD)
  fname_cvt = file_canonical_name (fname, &is_allocated);
  if (!is_allowed (fname_cvt))
    {
      if (is_allocated)
	dk_free (fname_cvt, -1);
      sqlr_new_error ("42000", "FA023",
	  "Access to %s is denied due to access control in ini file", fname);
    }

  if (0 != chmod (fname_cvt, mod))
    {
      int eno = errno;
      res = box_dv_short_string (strerror (eno));
    }
  else
    res = NEW_DB_NULL;
#else
  res = box_dv_short_string ("Feature not available in the host OS");
#endif

  if (is_allocated)
    dk_free (fname_cvt, -1);
  return res;
}

static dk_mutex_t *pwnam_mutex;

caddr_t
os_get_uname_by_uid (long uid)
{
  caddr_t res = NULL;
#if defined (HAVE_GETPWUID)
  struct passwd *pwd;
  mutex_enter (pwnam_mutex);
  pwd = getpwuid ((uid_t) uid);
  if (pwd)
    res = box_dv_short_string (pwd->pw_name);
  mutex_leave (pwnam_mutex);
#endif

  if (!res)
    res = NEW_DB_NULL;
  return res;
}

caddr_t
os_get_gname_by_gid (long gid)
{
  caddr_t res = NULL;
#if defined (HAVE_GETPWUID)
  struct group *grp;
  mutex_enter (pwnam_mutex);
  grp = getgrgid ((gid_t) gid);
  if (grp)
    res = box_dv_short_string (grp->gr_name);
  mutex_leave (pwnam_mutex);
#endif

  if (!res)
    res = NEW_DB_NULL;
  return res;
}

#ifdef WIN32
#include <Aclapi.h>

caddr_t
os_get_uname_by_fname (char *fname)
{
  caddr_t ret = NULL;
  PSID owner = 0;

  if (ERROR_SUCCESS == GetNamedSecurityInfo (fname, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION, &owner, NULL, NULL, NULL, NULL))
    {
      char name[1000], dname[1000];
      DWORD l_name = sizeof (name);
      DWORD l_dname = sizeof (dname);
      SID_NAME_USE use;
      if (LookupAccountSid (NULL, owner, name, &l_name, dname, &l_dname, &use))
	{
	  ret = box_dv_short_string (name);
	}
    }
  return ret ? ret : NEW_DB_NULL;
}

caddr_t
os_get_gname_by_fname (char *fname)
{
  caddr_t ret = NULL;
  PSID owner = 0;

  if (ERROR_SUCCESS == GetNamedSecurityInfo (fname, SE_FILE_OBJECT, GROUP_SECURITY_INFORMATION, NULL, &owner, NULL, NULL, NULL))
    {
      char name[1000], dname[1000];
      DWORD l_name = sizeof (name);
      DWORD l_dname = sizeof (dname);
      SID_NAME_USE use;
      if (LookupAccountSid (NULL, owner, name, &l_name, dname, &l_dname, &use))
	{
	  ret = box_dv_short_string (name);
	}
    }
  return ret ? ret : NEW_DB_NULL;
}
#endif

static caddr_t
bif_os_chown (caddr_t * qst, caddr_t * err_ret, state_slot_t ** args)
{
  caddr_t fname = bif_string_arg (qst, args, 0, "os_chown");
  caddr_t user  = bif_string_arg (qst, args, 1, "os_chown");
  caddr_t group = bif_string_arg (qst, args, 2, "os_chown");
  char *fname_cvt = NULL;
  int is_allocated = 0;
  caddr_t res = NULL;

  sec_check_dba ((query_instance_t *) qst, "os_chown");

  fname_cvt = file_canonical_name (fname, &is_allocated);
  if (!is_allowed (fname_cvt))
    {
      if (is_allocated)
	dk_free (fname_cvt, -1);
      sqlr_new_error ("42000", "FA023",
	  "Access to %s is denied due to access control in ini file", fname);
    }

#if defined (HAVE_CHOWN) && defined (HAVE_GETPWNAM) && defined (HAVE_GETGRNAM)
    {
      char buffer[255];
      struct passwd *u_info = NULL;
      struct group *g_info = NULL;
      uid_t uid;
      gid_t gid;

      mutex_enter (pwnam_mutex);
      u_info = getpwnam (user);
      if (u_info)
	uid = u_info->pw_uid;

      g_info = getgrnam (group);
      if (g_info)
	gid = g_info->gr_gid;
      mutex_leave (pwnam_mutex);

      if (!res && !u_info)
	{
	  snprintf (buffer, sizeof (buffer), "User %.200s does not exist", user);
	  res = box_dv_short_string (buffer);
	}
      if (!res && !g_info)
	{
	  snprintf (buffer, sizeof (buffer), "Group %.200s does not exist", group);
	  res = box_dv_short_string (buffer);
	}

      if (!res)
	{
	  if (0 != chown (fname_cvt, uid, gid))
	    {
	      int eno = errno;
	      res = box_dv_short_string (strerror (eno));
	    }
	  else
	    res = NEW_DB_NULL;
	}
    }
#elif defined (WIN32)
    {
      SID_NAME_USE use_user = SidTypeUser, use_group = SidTypeGroup;
      char user_sid[SECURITY_MAX_SID_SIZE], group_sid[SECURITY_MAX_SID_SIZE], dom1[1000], dom2[1000];
      DWORD user_sid_sz = SECURITY_MAX_SID_SIZE, group_sid_sz = SECURITY_MAX_SID_SIZE, d1 = sizeof (dom1), d2 = sizeof (dom2);

      if (LookupAccountName (NULL, user, (PSID) user_sid, &user_sid_sz, dom1, &d1, &use_user) &&
	  LookupAccountName (NULL, group, (PSID) group_sid, &group_sid_sz, dom2, &d2, &use_group))
	{
	  if (ERROR_SUCCESS == SetNamedSecurityInfo (fname_cvt, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION | GROUP_SECURITY_INFORMATION,
		(PSID) user_sid, (PSID) group_sid, NULL, NULL))
	    res = NEW_DB_NULL;
	}
      if (!res)
	{
	  LPVOID lpMsgBuf;
	  if (FormatMessage(
		FORMAT_MESSAGE_ALLOCATE_BUFFER |
		FORMAT_MESSAGE_FROM_SYSTEM |
		FORMAT_MESSAGE_IGNORE_INSERTS,
		NULL,
		GetLastError(),
		MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), /* Default language */
		(LPTSTR) &lpMsgBuf,
		0,
		NULL ))
	    {
	      res = box_dv_short_string (lpMsgBuf);
	      LocalFree( lpMsgBuf );
	    }
	  else
	    res = box_dv_short_string ("Unknown Win32 error");
	}
    }
#else
  res = box_dv_short_string ("Feature not available in the host OS");
#endif

  if (is_allocated)
    dk_free (fname_cvt, -1);
  return res;
}


float compiler_unit_msecs = 0;

#define SQLO_NITERS 1000

#define COL_COUNT "select count (*) from SYS_COLS a where COL_DTP > 0 and exists (select 1 from SYS_COLS b table option (loop) where a.\"TABLE\" = b.\"TABLE\" and a.\"COLUMN\" = b.\"COLUMN\")"

void
srv_calculate_sqlo_unit_msec (void)
{
  caddr_t err = NULL;
  caddr_t score_box;
  float score;
  float start_time, end_time;
  local_cursor_t *lc_tim = NULL;
  query_t *qr = NULL;
  dbe_table_t *sys_cols_tb = sch_name_to_table (isp_schema (NULL), "DB.DBA.SYS_COLS");
  long old_tb_count;
  int inx;
  client_connection_t *cli = bootstrap_cli;

  old_tb_count = sys_cols_tb->tb_count;

  qr = sql_compile (COL_COUNT, cli, &err, SQLC_DEFAULT);
  start_time = (float) get_msec_real_time ();
  for (inx = 0; inx < SQLO_NITERS; inx++)
    { /* repeat enough times as sys_cols is usually not very big */
      err = qr_quick_exec (qr, cli, NULL, &lc_tim, 0);
      lc_next (lc_tim);
      sys_cols_tb->tb_count = (long) unbox (lc_nth_col (lc_tim, 0));
      lc_next (lc_tim);
      lc_free (lc_tim);
      if (inx > 0 && inx % 10 == 0 && get_msec_real_time () - start_time > 1000)
        {
          inx += 1;
          break;
        }
    }
  end_time = (float) get_msec_real_time ();
  qr_free (qr);

  score_box = (caddr_t) sql_compile (COL_COUNT, cli, &err, SQLC_SQLO_SCORE);
  score = unbox_float (score_box);
  dk_free_tree (score_box);
  compiler_unit_msecs = (end_time - start_time) / (score * inx);

  sys_cols_tb->tb_count = old_tb_count;
  local_commit (bootstrap_cli);
  log_info ("Compiler unit is timed at %f msec", (double) compiler_unit_msecs);
}


static caddr_t
bif_user_has_role (caddr_t * qst, caddr_t * err_ret, state_slot_t ** args)
{
  caddr_t uname = bif_string_arg (qst, args, 0, "user_has_role");
  caddr_t rname = bif_string_arg (qst, args, 1, "user_has_role");
  user_t **place;
  user_t *usr;
  int inx;

  sec_check_dba ((query_instance_t *) qst, "user_has_role");
  place = (user_t **) id_hash_get (sec_users, (caddr_t) &uname);

  if (!place)
    sqlr_new_error ("22023", "SR390", "No such user %s in user_has_role", uname);

  usr = *place;
  DO_BOX (ptrlong, g_id, inx, usr->usr_g_ids)
    {
      user_t *gr = sec_id_to_user ((oid_t) g_id);
      if (!strcmp (gr->usr_name, rname))
	return box_num (1);
    }
  END_DO_BOX;
  return box_num (0);
}


static caddr_t
bif_client_attr (caddr_t * qst, caddr_t * err_ret, state_slot_t ** args)
{
  query_instance_t * qi = (query_instance_t *) qst;
  caddr_t mode = bif_string_arg (qst, args, 0, "client_attr");
  session_t *ses;

  if (!stricmp ("client_protocol", mode))
    {
      if (qi->qi_client->cli_ws && qi->qi_client->cli_ws->ws_proto)
	return box_dv_short_string (qi->qi_client->cli_ws->ws_proto);
      else
	return box_dv_short_string ("SQL");
    }
  else if (!stricmp ("client_ip", mode))
    {
      return int_client_ip (qi, 0);
    }
  else if (!stricmp ("accepting_ip", mode))
    {
      char buf[100];

      if (!qi->qi_client->cli_ws && !qi->qi_client->cli_session)
	return box_dv_short_string ("127.0.0.1");

      ses = qi->qi_client->cli_ws && qi->qi_client->cli_ws->ws_session ?
	  qi->qi_client->cli_ws->ws_session->dks_session : qi->qi_client->cli_session->dks_session;

      if (!tcpses_getsockname (ses, buf, sizeof (buf)))
	{
#ifdef COM_UNIXSOCK
	    {
	      int port;
	      if (!strncmp (buf, UNIXSOCK_ADD_ADDR, sizeof (UNIXSOCK_ADD_ADDR) - 1)
		  && (port = atoi (buf + sizeof (UNIXSOCK_ADD_ADDR) - 1)))
		snprintf (buf, sizeof (buf), "127.0.0.1:%d", port);
	    }
#endif
	  return box_dv_short_string (buf);
	}

      *err_ret = srv_make_new_error ("22005", "SR401", "Server address not known");
    }
  else if (!stricmp ("client_application", mode))
    {
      if (qi->qi_client->cli_user_info)
	return box_dv_short_string (qi->qi_client->cli_user_info);
    }
  else if (!stricmp ("client_ssl", mode))
    {
#ifdef _SSL
      SSL *ssl = (SSL *) tcpses_get_ssl (qi->qi_client->cli_ws ?
	  qi->qi_client->cli_ws->ws_session->dks_session :
	     qi->qi_client->cli_session->dks_session);
      if (ssl)
	return box_num (1);
#else
      sqlr_new_error ("22005", "SR403", "'client_ssl' value of client_attr option is not supported by this build of the Virtuoso server");
      return NULL;
#endif
    }
  else if (!stricmp ("client_certificate", mode))
    {
#ifdef _SSL
      caddr_t ret = NULL;
      char *ptr;
      SSL *ssl = (SSL *) tcpses_get_ssl (qi->qi_client->cli_ws ?
	  qi->qi_client->cli_ws->ws_session->dks_session :
	     qi->qi_client->cli_session->dks_session);
      X509 *cert = NULL;
      BIO *in = NULL;

      if (ssl)
        cert = SSL_get_peer_certificate (ssl);
      else
	return NULL;

      in = BIO_new (BIO_s_mem());

      if (!in)
	{
	  char err_buf[512];
	  sqlr_new_error ("22005", "SR402", "Cannot allocate temp space. SSL error : %s",
	      get_ssl_error_text (err_buf, sizeof (err_buf)));
	  return NULL;
	}

      BIO_reset(in);

      PEM_write_bio_X509 (in, cert);
      ret = dk_alloc_box (BIO_get_mem_data (in, &ptr) + 1, DV_SHORT_STRING);
      memcpy (ret, ptr, box_length (ret) - 1);
      ret[box_length (ret) - 1] = 0;

      BIO_free (in);

      return ret;
#else
      sqlr_new_error ("22005", "SR403", "'client_certificate' value of client_attr option is not supported by this build of the Virtuoso server");
      return NULL;
#endif
    }
  else if (!stricmp ("transaction_log", mode))
    {
      int is_on = 1;
      if (srv_have_global_lock (THREAD_CURRENT_THREAD))
	is_on = 0;
      else if (qi->qi_trx->lt_replicate == REPL_NO_LOG)
        is_on = 0;
      return box_num (is_on);
    }
  else
    {
      *err_ret = srv_make_new_error ("22005", "SR403", " %s is not valid client_attr option", mode);
    }

  return NULL;
}


static caddr_t
bif_sql_warnings_resignal (caddr_t * qst, caddr_t * err_ret, state_slot_t ** args)
{
  caddr_t *warnings = (caddr_t *) bif_array_or_null_arg (qst, args, 0, "sql_warnings_resignal");

  if (warnings)
    {
      int inx;

      if (DV_ARRAY_OF_POINTER != DV_TYPE_OF (warnings))
	sqlr_new_error ("22023", "SR454", "Invalid warnings array");

      DO_BOX (caddr_t,  warning, inx, warnings)
	{
	  if (!IS_BOX_POINTER (warning) ||
	      DV_ARRAY_OF_POINTER != DV_TYPE_OF (warning) ||
	      BOX_ELEMENTS (warning) != 3 ||
	      (((caddr_t*) warning)[0]) != (caddr_t) QA_WARNING ||
	      (!DV_STRINGP (ERR_STATE (warning)) && DV_C_STRING != DV_TYPE_OF (ERR_STATE (warning))) ||
	      (!DV_STRINGP (ERR_MESSAGE (warning)) && DV_C_STRING != DV_TYPE_OF (ERR_MESSAGE (warning))))
	    sqlr_new_error ("22023", "SR455", "Invalid warning in the warnings array");

	  sql_warning_add (box_copy_tree (warning), 0);
	}
      END_DO_BOX;
    }
  return NEW_DB_NULL;
}


static caddr_t
bif_sql_warning (caddr_t * qst, caddr_t * err_ret, state_slot_t ** args)
{
  caddr_t sql_state = bif_string_arg (qst, args, 0, "sql_warning");
  caddr_t virt_code = bif_string_arg (qst, args, 1, "sql_warning");
  caddr_t msg = bif_string_arg (qst, args, 2, "sql_warning");

  sqlr_warning (sql_state, virt_code, "%s", msg);
  return NEW_DB_NULL;
}


static caddr_t
bif_sec_uid_to_user (caddr_t * qst, caddr_t * err_ret, state_slot_t ** args)
{
  oid_t uid = (oid_t) bif_long_arg (qst, args, 0, "__sec_uid_to_user");
  user_t *user;

  user = sec_id_to_user (uid);
  if (user)
    return box_dv_short_string (user->usr_name);
  else
    return NEW_DB_NULL;
}

static caddr_t
bif_current_proc_name (caddr_t * qst, caddr_t * err_ret, state_slot_t ** args)
{
  query_instance_t * qi = (query_instance_t *) qst;
  if (IS_POINTER (qi) && qi->qi_query && qi->qi_query->qr_proc_name)
    return box_string (qi->qi_query->qr_proc_name);
  return NEW_DB_NULL;
}

void
sqlbif2_init (void)
{
  pwnam_mutex = mutex_allocate ();
  mutex_option (pwnam_mutex, "pwnam_mutex", NULL, NULL);
  bif_define ("__ddl_read_constraints", bif_ddl_read_constraints);
  bif_define_typed ("sys_lockdown", bif_sys_lockdown, &bt_integer);
  bif_define_typed ("__blob_handle_from_session", bif_blob_handle_from_session, &bt_blob_handle);
  bif_define_typed ("os_chmod", bif_os_chmod, &bt_varchar);
  bif_define_typed ("os_chown", bif_os_chown, &bt_varchar);
  bif_define_typed ("user_has_role", bif_user_has_role, &bt_integer);
  bif_define_typed ("client_attr", bif_client_attr, &bt_integer);
  bif_define ("sql_warning", bif_sql_warning);
  bif_define ("sql_warnings_resignal", bif_sql_warnings_resignal);
  bif_define_typed ("__sec_uid_to_user", bif_sec_uid_to_user, &bt_varchar);
  bif_define ("current_proc_name", bif_current_proc_name);
  sqls_bif_init ();
  sqlo_inv_bif_int ();
}
