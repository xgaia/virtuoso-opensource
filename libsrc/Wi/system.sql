--  
--  $Id$
--
--  This file is part of the OpenLink Software Virtuoso Open-Source (VOS)
--  project.
--  
--  Copyright (C) 1998-2006 OpenLink Software
--  
--  This project is free software; you can redistribute it and/or modify it
--  under the terms of the GNU General Public License as published by the
--  Free Software Foundation; only version 2 of the License, dated June 1991.
--  
--  This program is distributed in the hope that it will be useful, but
--  WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
--  General Public License for more details.
--  
--  You should have received a copy of the GNU General Public License along
--  with this program; if not, write to the Free Software Foundation, Inc.,
--  51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
--  
--  

create table SYS_VT_INDEX (VI_TABLE varchar, VI_INDEX varchar, VI_COL varchar,
	VI_ID_COL varchar, VI_INDEX_TABLE varchar,
       VI_ID_IS_PK integer, VI_ID_CONSTR varchar,
       VI_OFFBAND_COLS varchar, VI_OPTIONS varchar, VI_LANGUAGE varchar,
       primary key (VI_TABLE, VI_COL))
;

--!AWK PUBLIC
create procedure SQL_PROCEDURE_COLUMNS (
    in qual varchar,
    in owner varchar,
    in name varchar,
    in col varchar,
    in casemode integer,
    in is_odbc3 integer
    )
{
  declare PROCEDURE_CAT, PROCEDURE_SCHEM, PROCEDURE_NAME, COLUMN_NAME, TYPE_NAME, REMARKS varchar;
  declare COLUMN_SIZE, BUFFER_LENGTH integer;
  declare COLUMN_TYPE, DATA_TYPE, DECIMAL_DIGITS, NUM_PREC_RADIX, NULLABLE smallint;

  declare COLUMN_DEF, IS_NULLABLE varchar;
  declare SQL_DATA_TYPE, SQL_DATETIME_SUB smallint;
  declare CHAR_OCTET_LENGTH, ORDINAL_POSITION integer;


  result_names (PROCEDURE_CAT, PROCEDURE_SCHEM, PROCEDURE_NAME, COLUMN_NAME,
      COLUMN_TYPE, DATA_TYPE, TYPE_NAME, COLUMN_SIZE, BUFFER_LENGTH,
      DECIMAL_DIGITS, NUM_PREC_RADIX, NULLABLE, REMARKS,
      COLUMN_DEF, SQL_DATA_TYPE, SQL_DATETIME_SUB, CHAR_OCTET_LENGTH, ORDINAL_POSITION, IS_NULLABLE);

  declare full_name varchar;
  declare inx, sz integer;
  declare cols, elt any;

  full_name := name;
  if (owner is not null)
      full_name := concat (owner, '.', full_name);
  else if (qual is not null)
      full_name := concat ('.', full_name);

  if (qual is not null)
    full_name := concat (qual, '.', full_name);

  for
     select
       P_NAME
     from DB.DBA.SYS_PROCEDURES
     where
       either (casemode, upper (P_NAME), P_NAME) like either (casemode, upper (full_name), full_name)
  do
    {
      cols := procedure_cols (P_NAME);
      if (cols)
	{
	  sz := length (cols);
	  inx := 0;
	  while (inx < sz)
	    {
	      elt := aref (cols, inx);
	      if (either (casemode, upper (aref (elt, 3)), aref (elt, 3)) like
		  either (casemode, upper (col), col))
		{
		  result (
		     aref (elt, 0),
		     aref (elt, 1),
		     aref (elt, 2),
		     aref (elt, 3),
		     aref (elt, 4),
		     either (is_odbc3, dv_to_sql_type3 (aref (elt, 5)), dv_to_sql_type (aref (elt, 5))),
		     dv_type_title (aref (elt, 5)),
		     aref (elt, 7),
		     aref (elt, 7),
		     aref (elt, 6),
		     10,
		     aref (elt, 8),
		     NULL,

		     NULL,
		     either (is_odbc3, dv_to_sql_type3 (aref (elt, 5)), dv_to_sql_type (aref (elt, 5))),
		     NULL,
		     aref (elt, 7),
		     aref (elt, 9),
		     either (aref (elt, 8), 'YES', 'NO')
		     );
		}
	      inx := inx + 1;
	    }
	}
    }
}
;

--!AWK PUBLIC
create procedure XML_URI_RESOLVE_LIKE_GET (in base_uri varchar, in rel_uri varchar, in output_charset varchar := null) returns any
{
  declare s_uri any;
  -- dbg_obj_princ ('XML_URI_RESOLVE_LIKE_GET (', base_uri, rel_uri, ')');
  if (__tag (base_uri) in (225, 226))
    base_uri := charset_recode (base_uri, '_WIDE_', 'UTF-8');
  else
    base_uri := coalesce (cast (base_uri as varchar), '');
  if (__tag (rel_uri) in (225, 226))
    rel_uri := charset_recode (rel_uri, '_WIDE_', 'UTF-8');
  else
    rel_uri := coalesce (cast (rel_uri as varchar), '');

  s_uri := WS.WS.PARSE_URI (base_uri);
  if (aref (s_uri, 0) = '')
    base_uri := sprintf ('http://%s', base_uri);
--  IvAn/UriSlash/011111 This causes violations of RFC 1808 on reading compound XML documents!
--  if (aref (base_uri, length (base_uri) - 1) <> ascii ('/'))
--    base_uri := concat (base_uri, '/');
  base_uri := WS.WS.EXPAND_URL (base_uri, rel_uri);
  -- dbg_obj_princ ('base_uri after WS.WS.EXPAND_URL in XML_URI_RESOLVE_LIKE_GET is ', base_uri);
  return charset_recode (base_uri, 'UTF-8', output_charset);
}
;

create function XML_URI_GET_AND_CACHE (in absolute_uri varchar)
{
  declare head, content any;
  whenever not found goto try_http_get;
   -- dbg_obj_princ ('XML_URI_GET_AND_CACHE (', absolute_uri, ')');
  if (__tag (absolute_uri) in (225, 226))
    absolute_uri := charset_recode (absolute_uri, '_WIDE_', 'UTF-8');
  else
    absolute_uri := charset_recode (absolute_uri, NULL, 'UTF-8');
  select CRES_CONTENT into content from DB.DBA.SYS_CACHED_RESOURCES where CRES_URI = absolute_uri;
  return content;
try_http_get:
  content := http_get (absolute_uri, head);
  if (aref (head, 0) not like '% 200%')
    signal ('H0001', concat ('HTTP GET failed for ', absolute_uri, ': ', aref (head, 0)));
  insert into DB.DBA.SYS_CACHED_RESOURCES
    (CRES_URI, CRES_CONTENT, CRES_LOADING_DATE)
    values
    (absolute_uri, content, now());
  return content;
}
;


--!AWK PUBLIC
create procedure XML_URI_PARSE_VIRT (in base_uri varchar, inout table_name varchar, inout datacol_name varchar, inout pathcol_name varchar, inout path varchar)
{
  declare table_start, col_start, path_start integer;
  declare inx integer;
   -- dbg_obj_princ ('XML_URI_PARSE_VIRT (', base_uri, ',...)');
  inx := 5;
  while (length (base_uri) > inx + 1 and
    aref (base_uri, inx) = ascii ('/'))
  inx := inx + 1;
  table_start := inx;
  path_start := locate (':', base_uri, table_start);
  if (path_start = 0)
	signal ('HT421', concat ('Non-valid Virtuoso uri (missing path separator): ', base_uri));
  path := subseq (base_uri, path_start);
  table_name := subseq (base_uri, table_start, path_start - 1);

  col_start := strrchr (table_name, '.');
  if (col_start is null)
	signal ('HT422',
  concat ('Non-valid Virtuoso uri (missing data column separator in the column ref): ', base_uri));
  datacol_name := subseq (table_name, col_start + 1);
  table_name := subseq (table_name, 0, col_start);


  col_start := strrchr (table_name, '.');
  if (col_start is null)
	signal ('HT423',
  concat ('Non-valid Virtuoso uri (missing path column separator in the column ref): ', base_uri));
  pathcol_name := subseq (table_name, col_start + 1);
  table_name := subseq (table_name, 0, col_start);
}
;



create procedure XML_URI_GET (in base_uri varchar, in rel_uri varchar)
{
  declare head, str, proto varchar;
  declare inx integer;
  declare s_uri any;
  -- dbg_obj_princ ('XML_URI_GET (', base_uri, rel_uri, ')');
  base_uri := XML_URI_RESOLVE_LIKE_GET (base_uri, rel_uri);
  -- dbg_obj_princ ('base URI after XML_URI_RESOLVE_LIKE_GET:', base_uri);
  if (__tag (base_uri) in (225, 226))
    base_uri := charset_recode (base_uri, '_WIDE_', 'UTF-8');
  else
    base_uri := charset_recode (base_uri, NULL, 'UTF-8');
again:
  s_uri := WS.WS.PARSE_URI (base_uri);
  str := null;
  proto := aref (s_uri, 0);
try_all:
  if (proto = 'http' or proto = 'https')
    {
      declare hcli_uid, hcli_pwd any;
      if (base_uri like 'http://www.w3.org/TR/%')
        return XML_URI_GET_AND_CACHE (charset_recode (base_uri, 'UTF-8', '_WIDE_'));
      if (base_uri like 'http://localdav.virt/%')
        {
	  base_uri := 'virt://WS.WS.SYS_DAV_RES.RES_FULL_PATH.RES_CONTENT:' || subseq (base_uri, 20);
          goto again;
	}
      whenever not found goto try_http_get;
      select CRES_CONTENT into str from DB.DBA.SYS_CACHED_RESOURCES where CRES_URI = base_uri;
      return str;
try_http_get:

      -- If http client credentials are specified
      hcli_uid := connection_get ('HTTP_CLI_UID');
      hcli_pwd := connection_get ('HTTP_CLI_PWD');
      declare _auth_get varchar;
      if ( (hcli_pwd is null) and (hcli_uid is null) )
	{
	  _auth_get := HTTP_GET_AUTH_INFO (base_uri); -- charset_recode here?
	  if (_auth_get is not null)
	    {
	      hcli_uid := aref (_auth_get, 0);
	      hcli_pwd := aref (_auth_get, 1);
	    }
	}
      if (lcase (base_uri) like 'http://local.virt/dav/%')
	{
	  proto := 'virt';
	  base_uri := 'virt://WS.WS.SYS_DAV_RES.RES_FULL_PATH.RES_CONTENT:' || subseq (base_uri, 17);
	  goto try_all;
	}
      else if (proto = 'https' or (length (hcli_uid) and length (hcli_pwd)))
        {
	  str := http_client_ext (url=>base_uri, uid=>hcli_uid, pwd=>hcli_pwd, headers=>head);
 	}
      else
        str := http_get (base_uri, head);
      if (aref (head, 0) not like '% 200%')
	signal ('H0001', concat ('HTTP request failed: ', aref (head, 0), 'for URI ', base_uri));
    }
  else if (proto = 'file')
    {
      inx := 5;
      base_uri := charset_recode (base_uri, 'UTF-8', NULL);
      while (length (base_uri) > inx + 1 and
	  aref (base_uri, inx) = ascii ('/'))
	inx := inx + 1;
      str := file_to_string (concat (http_root(), '/' , subseq (base_uri, inx)));
    }
  else if (proto = 'virt')
    {
      declare datacol_name, path, table_name, pathcol_name varchar;
      declare path1 any;
       -- dbg_obj_princ ('base URI before charset recode:', base_uri);
      base_uri := charset_recode (base_uri, 'UTF-8', NULL);
       -- dbg_obj_princ ('base URI after charset recode:', base_uri);
      XML_URI_PARSE_VIRT (base_uri, table_name, datacol_name, pathcol_name, path);

      declare st, msg varchar;
      st := '00000';


      if (__any_grants_to_user (table_name, USER, 1))
	goto skip_auth;
      if (0 = casemode_strcmp (table_name, 'WS.WS.SYS_DAV_RES'))
	{
          declare _dav_user_id integer;
	  _dav_user_id := connection_get ('DAVUserID');
	  -- this is wrong, the included files must be tested against resource owner if they are executable
	  -- skip if virtual directory is executable and requested file is an child
	  --if (is_http_ctx () and http_map_get ('executable') and path like concat (http_map_get ('mounted'),'%'))
	  --  goto skip_auth;
	  if (0 = WS.WS.CHECKPERM (WS.WS.HREF_TO_ARRAY (path, ''), _dav_user_id, '100'))
	    {
	      if (is_http_ctx() and not http_map_get ('executable'))
		{
		  -- if we are in the HTTP context let do authentication
		  DB.DBA.vsp_auth_get ('DAV', '/DAV',
		      md5 (datestring(now())),
		      md5 ('opaakki'),
		      'false', http_request_header (), 1);
	          signal ('VSPRT', concat ('Not authorized to read from ', base_uri));
		}
	      signal ('42000', concat ('Not authorized to read from ', base_uri));
	    }
	}
      else
	{
          declare _dav_user_id integer;
	  _dav_user_id := connection_get ('DAVUserID');
	  if (isinteger (_dav_user_id) and 0 = __any_grants_to_user (table_name, NULL, 1))
	    signal ('42000', concat ('Not authorized  to read from ', base_uri));
	}
skip_auth:;

      path1 := path;
      -- try to cast the path to the type of column
      {
	  declare tp integer;
	  declare cl cursor for select COL_DTP from DB.DBA.SYS_COLS
	      where 0 = casemode_strcmp ("TABLE", complete_table_name (table_name, 1))
	            and 0 = casemode_strcmp ("COLUMN", pathcol_name);
          tp := 0;
	  whenever not found goto cl_err;
	  open cl (prefetch 1);
	  fetch cl into tp;
	  if (tp = 189 or tp = 188)
	    path1 := cast (path as integer);
	  else if (tp = 191 or tp = 190)
	    path1 := cast (path as double precision);
	  else if (tp = 211 or tp = 128 or tp = 129)
	    path1 := cast (path as datetime);
	cl_err:;
	  close cl;
      }

      exec (concat ('select "', datacol_name, '" from "', table_name, '" where "', pathcol_name, '" = ?'),
	  st, msg, vector (path1), 1, null, str);
      if (st <> '00000')
	signal (st, msg);
      if (isarray (str) and length (str) > 0)
	{
	  str := aref (str, 0);
	  if (isarray (str) and length (str) > 0)
	    str := aref (str, 0);
	}
      if (isblob (str))
	return str;
      if (isentity (str))
	return str;
      if (isstring (str) = 0)
        {
          if (0 = casemode_strcmp (table_name, 'WS.WS.SYS_DAV_RES'))
            {
              declare content, type any;
              declare id any;
              declare rc integer;
              id := DAV_SEARCH_ID (path, 'R');
              if (isinteger (id))
                if (id < 0)
		  signal ('42000', concat ('DAV doesn''t contain resource with path equal to "', path, '"'));
              rc := DAV_RES_CONTENT_INT (id, content, type, 0, 0, null, null);
              if (isinteger (rc))
                if (rc < 0)
		  signal ('42000', concat ('Error on reading DAV resource with path equal to "', path, '"'));
	      return content;
            }
	  signal ('42000', concat ('The table ', table_name, ' doesn''t have row with ',
	      pathcol_name, ' equal to "', path, '"'));
	}
    }
  else if (proto like 'x-virt-cache-%')
    {
      declare content any;
      whenever not found goto cache_miss;
      select CRES_CONTENT into content from DB.DBA.SYS_CACHED_RESOURCES where CRES_URI = base_uri;
      return content;
cache_miss:
      signal ('HT068', sprintf ('Resource "%s" not found in SYS_CACHED_RESOURCES', base_uri));
    }
  else
    {
      signal ('HT424', sprintf ('Unsupported protocol %s', proto));
    }
  return str;
}
;

create procedure XML_URI_GET_STRING (in base_uri varchar, in rel_uri varchar)
{
  declare _res any;
  _res := XML_URI_GET (base_uri, rel_uri);
  if (isstring (_res))
    return _res;
  return cast (_res as varchar);
}
;

create procedure XML_URI_GET_STRING_OR_ENT (in base_uri varchar, in rel_uri varchar)
{
  declare _res any;
  _res := XML_URI_GET (base_uri, rel_uri);
  if (isstring (_res) or isentity (_res))
    return _res;
  return cast (_res as varchar);
}
;


create procedure XML_COLLECTION_DIR_LIST_LOCAL (in collection_uri varchar, in dav_path varchar, inout res any, in recursive int)
{
  declare dir_list any;
  declare r_dict, r_list any;
  -- dbg_obj_princ ('XML_COLLECTION_DIR_LIST_LOCAL (', collection_uri, dav_path, ', ...,', recursive, ')');
  dir_list := DAV_DIR_LIST_INT (dav_path, case recursive when 0 then 0 else 1 end, '%', null, null, http_dav_uid());
  if (not isarray (dir_list))
    return;
  r_dict := dict_new (length (dir_list) + 13);
  foreach (any dir_itm in dir_list) do
	{
      if ('R' = dir_itm[1])
	    {
          declare res_id any;
          declare res_path varchar;
          res_id := dir_itm[4];
          if (isarray (res_id))
	    {
              res_path := DAV_SEARCH_PATH (res_id, 'R');
              if (not isstring (res_path))
                res_path := dir_itm[0];
	    }
          else
            res_path := dir_itm[0];
          dict_put (r_dict, res_path, 0);
	}
    }
  r_list := dict_list_keys (r_dict, 2);
  gvector_sort (r_list, 1, 0, 1);
  foreach (varchar r_path in r_list) do
    xq_sequencebld_acc (res, subseq (collection_uri, 0, 22) || subseq (r_path, 5));
}
;

create procedure XML_COLLECTION_DIR_LIST_TABLE (in collection_uri varchar, inout res any, in recursive int)
{
  declare datacol_name, path, table_name, pathcol_name varchar;
  -- dbg_obj_princ ('XML_COLLECTION_DIR_LIST_TABLE (', collection_uri, ', ...)');
  XML_URI_PARSE_VIRT (collection_uri || ':_id', table_name, datacol_name, pathcol_name, path);

  if (__any_grants_to_user (table_name, USER, 1))
    goto skip_auth;
  if (0 = casemode_strcmp (table_name, 'WS.WS.SYS_DAV_RES'))
    {
      signal ('42000', 'Access to WS.WS.SYS_DAV_RES is not allowed by virt://... collection');
    }
  else
    {
      if (0 = __any_grants_to_user (table_name, NULL, 1))
	signal ('42000', concat ('Not authorized  to read from ', collection_uri));
    }
skip_auth:;

  declare st, msg varchar;
  declare stmt varchar;
  declare rows any;
  st := '00000';
  stmt := concat ('select "', pathcol_name, '" from "', table_name, '"');
  -- dbg_obj_print ('stmt=', stmt);
  exec (stmt, st, msg, null, 100, null, rows);
  if (st <> '00000')
	signal (st, msg);
  if (isarray (rows))
    {
	foreach (any _id in rows) do
	  xq_sequencebld_acc (res, concat ('virt://', table_name, '.', pathcol_name, '.', datacol_name, ':', cast (aref (_id, 0) as varchar)));
    }
}
;


create procedure HTTP_GET_AUTH_INFO (in base_uri varchar)
{
  declare _auth_get, hcli_uid, hcli_pwd varchar;
  _auth_get := connection_get ('HTTPAuthManager');
  if (_auth_get is not null)
    {
 	declare _st, _msg varchar;
	declare _auth_card any;
	_st := '00000';
	exec ('select "' || _auth_get || '"(?)', _st, _msg, vector (base_uri), 1, null, _auth_card);
	if (_st <> '00000')
		signal (_st, _msg);
	if (isarray (_auth_card) and isarray (aref (_auth_card, 0)) and isarray (aref (aref (_auth_card, 0), 0) ))
	  {
	    hcli_uid := aref (aref (aref (_auth_card, 0), 0), 0);
	    hcli_pwd := aref (aref (aref (_auth_card, 0), 0), 1);
	    if (isstring (hcli_pwd) and isstring (hcli_uid))
		return vector (hcli_uid, hcli_pwd);
	  }
	signal ('H0002', 'Authentication callback function returned wrong authentication info');
    }
  return null;
}
;


create procedure XML_COLLECTION_DIR_LIST_REMOTE (in host_part varchar, in auth_digest varchar, in dav_path varchar, inout res any, in recursive int)
{
  declare r any;
  declare b any;
  declare body, hdr varchar;
  declare _auth_get varchar;
  -- dbg_obj_princ ('XML_COLLECTION_DIR_LIST_REMOTE (', host_part, auth_digest, dav_path, ', ...,', recursive, ')');
  hdr := null;
  if (auth_digest is null)
    {
	_auth_get := HTTP_GET_AUTH_INFO (dav_path);
	if (_auth_get is not null)
	   hdr := 'Authorization: Basic ' || encode_base64 (aref (_auth_get, 0) || ':' || aref (_auth_get, 1));
    }
  else
    hdr := sprintf ('Authorization: Basic %s', auth_digest);
  b := http_get (dav_path, r, 'PROPFIND', hdr);
  if (isarray (r) and (aref (r, 0) not like 'HTTP/1.1 2__%'))
    {
	r := null;
	b := http_get (dav_path, r, 'GET', hdr);
	if (isarray (r) and (aref (r, 0) not like 'HTTP/1.1 2__%'))
	   signal ('H0001', concat ('HTTP request failed: ', aref (r, 0), 'for URI ', dav_path));
	b := xtree_doc (b, 2);
	declare _hrefs any;
	_hrefs := xpath_eval ('//a/@href', b, 0);
	if (isarray (_hrefs)) {
	  foreach (varchar uri in xpath_eval ('//a/@href', b, 0)) do
	    {
  		uri := lcase (uri);
		if (uri <> '..' and uri not like 'mailto:%') {
		  if (uri like 'http://%') {
		   xq_sequencebld_acc (res, uri);
 		  } else {
		   xq_sequencebld_acc (res, dav_path || uri);
		  }
	    	}
  	    }
	}
    }
  else
    {
	declare dav_part, file_part varchar;
	dav_part := subseq (dav_path, length (host_part));
	b := xtree_doc (b);
	foreach (any uri in xpath_eval ('distinct-values (/multistatus/response[not propstat/prop/resourcetype/collection]/href/text())', b)) do
	  {
	    if (recursive = 0)
	      {
		file_part := subseq (cast (uri as varchar), length (dav_part));
		if (strchr (file_part, '/') is null)
		    xq_sequencebld_acc (res, host_part || cast (uri as varchar));
	      }
	    else
		    xq_sequencebld_acc (res, host_part || cast (uri as varchar));

	  }
    }

}
;

create procedure XML_COLLECTION_DIR_LIST (in collection_uri any, in recursive int)
{
  declare res, uri_dict any;
  -- dbg_obj_princ ('XML_COLLECTION_DIR_LIST (', collection_uri, recursive, ')');
  if (isstring (collection_uri))
    {
	xq_sequencebld_init (res);
	declare lcase_collection_uri varchar;
 	declare dir_list any;
	declare dav_path varchar;
	lcase_collection_uri := lcase (collection_uri);
 	if (lcase_collection_uri like 'http://local.virt/dav/%')
	  dav_path := subseq (collection_uri, 17);
	else if ((lcase_collection_uri not like 'http://%') and (lcase_collection_uri not like '~%') and (lcase_collection_uri not like 'virt://%'))
 	  signal ('XXXXX', 'collection must begin with "http://"');
	else
	  dav_path := collection_uri;
	if ((dav_path not like '%/') and (dav_path not like 'virt://%'))
	  dav_path := dav_path || '/';
	if (dav_path like '~%')
	  {
	    declare _home, _uname, arr varchar;
	    arr := split_and_decode (dav_path, 0, '\0\0/');
	    if (isarray (arr) and (length (arr) > 0))
		_uname := subseq (aref (arr, 0), 1);
	    _home := (select U_HOME from SYS_USERS where U_NAME = _uname);
	    if (_home is null)
	      signal ('XXXXX', 'user ' || _uname || ' does not have home DAV collection');
	    dav_path := subseq (_home, 0, length (_home) - 1);
	    declare _idx int;
	    _idx := 1;
	    while (_idx < length (arr)) {
		dav_path := dav_path || '/' || aref (arr, _idx);
		_idx := _idx + 1;
	    }
	    collection_uri := 'http://local.virt' || dav_path;
	  }
	if (dav_path like '/DAV/%')
	  {
	    XML_COLLECTION_DIR_LIST_LOCAL (collection_uri, dav_path, res, recursive);
	  }
	else if (dav_path like 'virt://%')
	  {
	    XML_COLLECTION_DIR_LIST_TABLE (dav_path, res, recursive);
	  }
	else
	  {
	    declare host_part varchar;
	    declare hcli_uid, hcli_pwd varchar;
	    host_part := coalesce (regexp_match ('http://[^:/]*(:[0-9]+)?', dav_path), '');
	    hcli_uid := connection_get ('HTTP_CLI_UID');
 	    hcli_pwd := connection_get ('HTTP_CLI_PWD');
	    XML_COLLECTION_DIR_LIST_REMOTE (host_part,
		case when ((hcli_uid is not null) and (hcli_pwd is not null)) then encode_base64 (hcli_uid || ':' || hcli_pwd) else null end,
		dav_path, res, recursive);
	  }
	xq_sequencebld_final (res);
  	return res;
    }
}
;

grant execute on XML_COLLECTION_DIR_LIST to public
;


create procedure SYS_ALFANUM_NAME (in name varchar)
{
  declare inx, c integer;
--  name := ucase (name);
  inx :=0;
  while (inx < length (name)) {
    c := aref (name, inx);
    if (not ((c >= aref ('A', 0) and c <= aref ('Z', 0))
	     or (c >= aref ('a', 0) and c <= aref ('z', 0))
	     or (c >= aref ('0', 0) and c <= aref ('9', 0))))
      aset (name, inx, aref ('_', 0));
    inx := inx + 1;
  }
  return name;
}
;

--create procedure USER_SET_PASSWORD (in name varchar, in passwd varchar)
--{
--  declare _u_id, _u_group integer;
--  declare _u_data varchar;
--  select U_ID, U_GROUP into _u_id, _u_group from DB.DBA.SYS_USERS where U_NAME = USER;
--  if (not (_u_id = 0 or _u_group = 0))
--    signal ('42000', 'Function user_set_password restricted to dba group', 'SR285');
--  if (not exists (select 1 from DB.DBA.SYS_USERS where U_NAME = name))
--    signal ('42000', concat ('The user ''', name, ''' does not exist'), 'SR286');
--  if (not isstring (passwd) or length (passwd) < 1)
--    signal ('42000', concat ('The new password for ''', name, ''' cannot be empty'), 'SR287');
--  update DB.DBA.SYS_USERS set U_PASSWORD = pwd_magic_calc (name, passwd) where U_NAME = name;
--  select U_ID, U_GROUP, U_DATA into _u_id, _u_group, _u_data
--      from DB.DBA.SYS_USERS where U_NAME = name;
--  sec_set_user_struct (name, passwd, _u_id, _u_group, _u_data);
--  log_text ('sec_set_user_struct (?, ?, ?, ?, ?)', name, passwd, _u_id, _u_group, _u_data);
--  return 0;
--}
--;


--!AWK PUBLIC
create procedure SYS_COPY_TABLE (in source_tbl varchar, in dest_tbl varchar)
{
  declare src_meta, dest_meta any;
  declare comm, col_list varchar;
  declare inx integer;

  exec (sprintf ('select * from "%I"', source_tbl), NULL, NULL, NULL, 1, src_meta, NULL);
  exec (sprintf ('select * from "%I"', dest_tbl), NULL, NULL, NULL, 1, dest_meta, NULL);

  if (0 = isarray (src_meta) or 0 = isarray (aref (src_meta, 0)))
    signal ('42S22', sprintf ('No columns in the source table %s', src_meta), 'SR288');
  if (not isarray (dest_meta) or 0 = isarray (aref (src_meta, 0)))
    signal ('42S22', sprintf ('No columns in the source table %s', dest_meta), 'SR289');

  src_meta := aref (src_meta, 0);
  dest_meta := aref (dest_meta, 0);
  inx := 0;

  col_list := '';
  while (inx < length (src_meta))
    {
      declare col any;
      declare col_name varchar;
      declare col_dtp integer;
      declare inx1, have_match integer;

      col := aref (src_meta, inx);
      col_name := aref (col, 0);
      col_dtp := aref (col, 1);

      inx1 := 0;
      have_match := 0;

      while (inx1 < length (dest_meta) and have_match = 0)
	{
	  if (aref (aref (dest_meta, inx1), 0) = col_name and (aref (aref (dest_meta, inx1), 1) = col_dtp))
	    have_match := 1;
	  else
	    inx1 := inx1 + 1;
	}
      if (have_match = 0)
	signal ('42S22', sprintf ('The column %s in the source table %s doesn''t have a match in the destination table %s', col_name, source_tbl, dest_tbl), 'SR290');

      if (inx > 0)
	col_list := concat (col_list, ' , ');

      col_list := concat (col_list, sprintf ('"%I"', col_name));
      inx := inx + 1;
    }
  exec (sprintf ('insert into "%I" (%s) select %s from "%I"', dest_tbl, col_list, col_list, source_tbl));
}
;




--!AWK PUBLIC
create procedure ddl_pk_fill_pk_parts (in pk_id integer, in k_id integer, in n_k_parts integer)
{
  declare n_pk integer;
  select KEY_N_SIGNIFICANT into n_pk from DB.DBA.SYS_KEYS where KEY_ID = pk_id;
  for select KP_COL as pk_col from DB.DBA.SYS_KEY_PARTS where KP_KEY_ID = pk_id and KP_NTH < n_pk do
    {
      if (not (exists (select 1 from DB.DBA.SYS_KEY_PARTS where KP_KEY_ID = k_id and KP_COL = pk_col)))
      {
	insert into DB.DBA.SYS_KEY_PARTS (KP_KEY_ID, KP_NTH, KP_COL) values (k_id, n_k_parts, pk_col);
	n_k_parts := n_k_parts + 1;
      }
    }
}
;


--!AWK PUBLIC
create procedure ddl_pk_copy_inx (in tb varchar, in ntb varchar, in nk_id integer)
{

  declare k_id integer;
  for select
    KEY_NAME, KEY_ID as _KEY_ID, KEY_DECL_PARTS as _KEY_DECL_PARTS,
      KEY_CLUSTER_ON_ID, KEY_IS_UNIQUE, KEY_IS_OBJECT_ID
      from DB.DBA.SYS_KEYS where KEY_IS_MAIN = 0 and KEY_TABLE = tb
      and KEY_MIGRATE_TO is null do
	{
	  k_id := new_key_id (0);
	  insert into DB.DBA.SYS_KEYS (KEY_TABLE, KEY_NAME, KEY_ID, KEY_DECL_PARTS,
				KEY_CLUSTER_ON_ID, KEY_SUPER_ID, KEY_IS_UNIQUE, KEY_IS_OBJECT_ID)
	  values (ntb, KEY_NAME, k_id, _KEY_DECL_PARTS,
		  k_id, k_id, KEY_IS_UNIQUE, KEY_IS_OBJECT_ID);

	  insert into DB.DBA.SYS_KEY_PARTS (KP_KEY_ID, KP_NTH, KP_COL)
	  select k_id, KP_NTH, (select n.COL_ID from DB.DBA.SYS_COLS n where n."TABLE" = ntb and n."COLUMN" = c."COLUMN")
	  from DB.DBA.SYS_KEY_PARTS, DB.DBA.SYS_COLS c where KP_NTH < _KEY_DECL_PARTS and KP_KEY_ID = _KEY_ID
	  and c.COL_ID = KP_COL;
	  DB.DBA.ddl_pk_fill_pk_parts (nk_id, k_id, _KEY_DECL_PARTS);
	  if (KEY_IS_UNIQUE = 1)
	  update DB.DBA.SYS_KEYS set KEY_N_SIGNIFICANT = KEY_DECL_PARTS,
	  KEY_IS_MAIN = 0
	  where KEY_ID = k_id;
	  else
	  update DB.DBA.SYS_KEYS set KEY_N_SIGNIFICANT = (select count (*) from DB.DBA.SYS_KEY_PARTS where KP_KEY_ID = k_id),
	  KEY_IS_MAIN = 0
	  where KEY_ID = k_id;
	}
}
;


--!AWK PUBLIC
create procedure ddl_pk_change_1 (in tb varchar, in cols any)
{
  declare pk_id, nk_id, inx, cid integer;
  declare tname, tname_esc, st, msg, pk_name varchar;

  tname := complete_table_name ('TEMP__', 0);
  tname_esc := sprintf ('"%I"."%I"."%I"',
		 name_part (tname, 0), name_part (tname, 1), name_part (tname, 2));
  exec (concat ('drop table ', tname_esc), st, msg, vector ());
  select KEY_ID, KEY_NAME
      into pk_id, pk_name
      from DB.DBA.SYS_KEYS
      where KEY_TABLE = tb and KEY_IS_MAIN = 1 and KEY_MIGRATE_TO is null;
  nk_id := new_key_id (0);
  insert into DB.DBA.SYS_KEYS (KEY_TABLE, KEY_NAME, KEY_ID, KEY_DECL_PARTS, KEY_N_SIGNIFICANT,
			KEY_CLUSTER_ON_ID, KEY_SUPER_ID, KEY_IS_MAIN, KEY_IS_UNIQUE)
    values  (tname, pk_name, nk_id, length (cols), length (cols),
	     nk_id, nk_id, 1, 1);
  declare cr cursor for select
    "COLUMN",
    COL_DTP,
    COL_PREC,
    COL_SCALE,
    COL_CHECK,
    deserialize (COL_DEFAULT),
    COL_NTH,
    COL_NULLABLE from DB.DBA.SYS_COLS
    where concat ('', "TABLE") = tb order by COL_ID;
    whenever not found goto done;
    open cr;
    while (1)
      {
	declare _col1, _col2, _col3, _col4, _col5, _col6, _col7, _col8, _col9, _col10 any;
	fetch cr into  _col3, _col4, _col5, _col6, _col7, _col8, _col9, _col10;
        _col1 := new_col_id (0);
        _col2 := tname;
	insert into DB.DBA.SYS_COLS
	    (COL_ID, "TABLE", "COLUMN", COL_DTP, COL_PREC, COL_SCALE, COL_CHECK, COL_DEFAULT,
	      		COL_NTH, COL_NULLABLE)
	    values (_col1, _col2, _col3, _col4, _col5, _col6, _col7, serialize (_col8), _col9, _col10);
      }
done:
  close cr;
  whenever not found default;
  inx := 0;
  while (inx < length (cols))
    {
      cid := (select COL_ID from DB.DBA.SYS_COLS where "TABLE" = tname and 0 = casemode_strcmp (\COLUMN, aref (cols, inx)));
      if (cid is null)
       {
         txn_error (6);
	 signal ('42000', concat ('Column ', aref (cols, inx), ' not found in alter table'));
       }
      insert into DB.DBA.SYS_KEY_PARTS (KP_KEY_ID, KP_NTH, KP_COL) values (nk_id, inx, cid);
      inx := inx + 1;
    }
  DB.DBA.att_fill_non_pk_parts (tname, nk_id, inx);
  DB.DBA.ddl_pk_copy_inx (tb, tname, nk_id);
  __ddl_changed (tname);
  DB.DBA.SYS_COPY_TABLE (tb, tname);
}
;


--!AWK PUBLIC
create procedure ddl_pk_change_final (in tb varchar, in cols any)
{
  declare st, msg, tname, tname_esc, tb_esc varchar;
  tname := complete_table_name ('TEMP__', 0);
  tname_esc := sprintf ('"%I"."%I"."%I"',
		 name_part (tname, 0), name_part (tname, 1), name_part (tname, 2));
  tb_esc := sprintf ('"%I"."%I"."%I"',
		 name_part (tb, 0), name_part (tb, 1), name_part (tb, 2));
  update DB.DBA.SYS_TRIGGERS set T_TABLE = tname where T_TABLE = tb;
  exec (sprintf ('drop table %s', tb_esc), st, msg, vector ());
  update DB.DBA.SYS_TRIGGERS set T_TABLE = tb where T_TABLE = tname;
  exec (sprintf ('alter table %s rename %s', tname_esc, tb_esc), st, msg, vector ());
  commit work;
  --log_enable(0);
}
;


--!AWK PUBLIC
create procedure ddl_pk_modify_check (in tb varchar, in cols any)
{
  declare inx integer;
  declare pk_id integer;
  pk_id := (select KEY_ID from DB.DBA.SYS_KEYS where KEY_TABLE = tb and KEY_MIGRATE_TO is null and KEY_IS_MAIN = 1);
  if (exists (select 1 from DB.DBA.SYS_KEY_SUBKEY where SUB = pk_id)
      or exists (select 1 from DB.DBA.SYS_REMOTE_TABLE where RT_NAME = tb)
      or exists (select 1 from DB.DBA.SYS_VT_INDEX where VI_TABLE = tb)
      or exists (select 1 from DB.DBA.SYS_KEY_SUBKEY, DB.DBA.SYS_KEYS where SUPER = pk_id and KEY_ID = SUB and KEY_MIGRATE_TO is null)
      )
    signal ('42S11', 'Primary key modification is prohibited if: Table is a subtable or has subtables, is attached or has a free text index', 'SR291');
  inx := 0;
  while (inx < length (cols))
    {
      if (not exists (select 1 from DB.DBA.SYS_KEY_PARTS, DB.DBA.SYS_COLS where  KP_KEY_ID = pk_id and COL_ID = KP_COL and
		      0 = casemode_strcmp ("COLUMN", aref (cols, inx))))
	signal ('42S22', sprintf ('Bad new pk column %s in list', aref (cols, inx)), 'SR292');
      inx := inx + 1;
    }
}
;


--!AWK PUBLIC
create procedure ddl_pk_is_changed (in tb varchar, in cols any) returns integer
{
  declare inx integer;

  inx := 0;

  for select c."COLUMN" as _column from
    DB.DBA.SYS_COLS c, DB.DBA.SYS_KEYS k, DB.DBA.SYS_KEY_PARTS kp
    where
      c.COL_ID = kp.KP_COL and
      kp.KP_KEY_ID = k.KEY_ID and
      k.KEY_TABLE = tb and
      k.KEY_IS_MAIN = 1 and
      k.KEY_MIGRATE_TO is null and
      kp.KP_NTH < k.KEY_N_SIGNIFICANT
      order by kp.KP_NTH do
	{
          if (inx >= length (cols))
	    return 1;
	  if (_column <> cols[inx])
	    return 1;
          inx := inx + 1;
	}
  if (inx <> length (cols))
    return 1;
  else
    return 0;
}
;


--!AWK PUBLIC
create procedure ddl_pk_modify (in tb varchar, in cols any)
{
  --dbg_obj_print (tb, cols);

  declare st, msg varchar;
  st := '00000';
  log_enable(0);
  DB.DBA.ddl_pk_modify_check (tb, cols);
  if (not DB.DBA.ddl_pk_is_changed (tb, cols))
    {
      log_enable (1);
      return;
    }
  __atomic (1);
  exec ('DB.DBA.ddl_pk_change_1 (?, ?)', st, msg, vector (tb, cols));
  if (st <> '00000')
    {
      declare tname, tname_esc varchar;
      tname := complete_table_name ('TEMP__', 0);
      tname_esc := sprintf ('"%I"."%I"."%I"',
		     name_part (tname, 0), name_part (tname, 1), name_part (tname, 2));
      declare st1, msg1 varchar;
      exec (concat ('drop table ', tname_esc), st1, msg1, vector ());
      __atomic (0);
      commit work;
      log_enable(0);
      signal (st, msg);
    }

  exec ('DB.DBA.ddl_pk_change_final (?, ?)', st, msg, vector (tb, cols));
  if (st <> '00000')
    {
      -- log_error ("DDL operation failed unrecoverable. Please restart the server. The effect of the aborted operation will not be seen after restart');
      raw_exit (1);
    }
  log_enable (1);
  log_text ('DB.DBA.ddl_pk_modify (?, ?)', tb, cols);
  commit work;
  __atomic (0);
}
;

create procedure DB.DBA.fk_check_input_values (in mod integer)
{
  declare ret, ret1 any;
  ret1 := registry_get ('FK_UNIQUE_CHEK');
  if (ret1 = 'ON')
    ret := 1;
  else
    ret := 0;

  if (mod = 1)
    registry_set ('FK_UNIQUE_CHEK', 'ON');
  else if (mod = 0)
    registry_set ('FK_UNIQUE_CHEK', 'OFF');
  else if (mod = -1)
    {
      if (not (ret1 = 'ON' or ret1 = 'OFF'))
	registry_set ('FK_UNIQUE_CHEK', 'ON');
    }
  else
    signal ('22023', 'function fk_check_input_values expect -1, 0 or 1 as first parameter', 'SR293');
  return ret;
}
;

DB.DBA.fk_check_input_values (-1)
;


create procedure DB.DBA.ddl_check_constraint (in pk_table varchar, in decl any)
{
  declare inx, n_pc, n_pkc integer;
  declare pk_col_name, uniq, col_name varchar;
  declare pkc, pkcols any;
  declare k_id, parts integer;
  declare iu cursor for select SC."COLUMN"
      from  DB.DBA.SYS_KEY_PARTS KP, DB.DBA.SYS_COLS SC
      where KP.KP_KEY_ID = k_id and SC.COL_ID = KP.KP_COL;


  pkcols := aref (decl, 3);
  inx := 0;
  n_pc := length (pkcols);
  pkc := DB.DBA.ddl_table_pk_cols (pk_table);
--  dbg_obj_print ('def: ', pkcols, '\nPK: ', pkc);
  n_pkc := length (pkc);
  while (inx < n_pc)
    {
      pk_col_name := convert (varchar, aref (pkcols, inx));
      if (not exists (select 1 from DB.DBA.SYS_KEY_COLUMNS
	    where "KEY_TABLE" = pk_table and 0 = casemode_strcmp ("COLUMN", pk_col_name)) and
	  not exists (select 1 from DB.DBA.SYS_COLS
	    where "TABLE" = pk_table and 0 = casemode_strcmp ("COLUMN", pk_col_name)))
	signal ('42S22', sprintf ('Foreign key references invalid column "%s" in referenced table "%s"',
	      pk_col_name, pk_table), 'SR294');
       inx := inx + 1;
    }

  uniq := registry_get ('FK_UNIQUE_CHEK');

  if (uniq <> 'ON')
    return;
  -- first we check primary key constraint of PK table
  if (n_pc = n_pkc)
    {
      inx := 0;
      while (inx < n_pc)
	{
	  pk_col_name := convert (varchar, aref (pkcols, inx));
	  if (0 <> casemode_strcmp (pk_col_name, aref (pkc, inx)))
	    goto unq_check;
	  inx := inx + 1;
	}
      return;
    }

unq_check:
  -- second we check for unique indexes on PK table
  for select KEY_ID, KEY_DECL_PARTS from DB.DBA.SYS_KEYS
    where 0 = casemode_strcmp (KEY_TABLE, pk_table) and KEY_IS_MAIN = 0 and KEY_IS_UNIQUE = 1 do {
      k_id := KEY_ID; parts := KEY_DECL_PARTS;
      if (n_pc = parts and parts > 0)
	{
	  whenever not found goto uk_done;
	  open iu;
	  inx := 0;
	  while (inx < parts)
	    {
	      pk_col_name := convert (varchar, aref (pkcols, inx));
	      fetch iu into col_name;
	      if (0 <> casemode_strcmp (pk_col_name, col_name))
		goto uk_done;
	      inx := inx + 1;
	    }
	  uk_done:
	  close iu;
	  -- if all columns for the index matched unique condition is done
	  if (inx = parts)
	    return;
	}
    }

  -- third we check all columns of PK for identities
  inx := 0;
  while (inx < n_pc)
    {
      pk_col_name := convert (varchar, aref (pkcols, inx));
      if (not exists (select 1 from DB.DBA.SYS_KEY_COLUMNS where "KEY_TABLE" = pk_table
	    and 0 = casemode_strcmp ("COLUMN", pk_col_name) and COL_CHECK = 'I'))
	signal ('37000', sprintf ('Foreign key references non-unique column "%s" in table "%s"',
	      pk_col_name, pk_table), 'SR295');
      inx := inx + 1;
    }
}
;


create procedure ddl_fk_modify (in tb varchar, in op integer, in decl any)
{
  declare pkt varchar;
  declare fkn any;
  if (isstring (aref (decl, 2)))
    pkt := complete_table_name (aref (decl, 2), 1);
  else
    pkt := null;

  if (op = 1 and pkt is null)
    signal ('37000', 'To add foreign key REFERENCES should be specified', 'SR296');

  fkn := aref (decl, 7);

  if (op = 1)
    ddl_foreign_key (tb, pkt, decl);
  else if (op = 2)
    {
      if (pkt is not null)
	{
          declare inx, n_fc, n_pc integer;
          declare fk_col_name, pk_col_name, fnam, fnam1, lastf varchar;
	  if (not exists (select 1 from DB.DBA.SYS_FOREIGN_KEYS where FK_TABLE = tb and PK_TABLE = pkt))
	    signal ('42S12', sprintf ('Foreign key does not exist in table "%s" referencing table "%s"', tb, pkt), 'SR297');

	  -- we need to ensure right key
	  if (0 = isarray (aref (decl, 3)) or 0 = length (aref (decl, 3)))
	    aset (decl, 3, ddl_table_pk_cols (pkt));
	  else
	    DB.DBA.ddl_check_constraint (pkt, decl);

	  n_fc := length (aref (decl, 1));
	  n_pc := length (aref (decl, 3));
	  if (n_fc <> n_pc)
	    signal ('37000',
		concat ('Different number of referencing and referenced columns in foreign key declaration from ',
		  tb, ' to ', pkt), 'SQ125');

          inx := 0; fnam := '';
          while (inx < n_pc)
            {
	      fk_col_name := convert (varchar, aref (aref (decl, 1), inx));
	      pk_col_name := convert (varchar, aref (aref (decl, 3), inx));
    	      fnam := concat (fnam, '_', convert (varchar, aref (aref (decl, 1), inx)), '_',
	      		 convert (varchar, aref (aref (decl, 3), inx)));
              inx := inx + 1;
	    }

          fnam1 := ''; lastf := '';
	  for select FK_NAME, FKCOLUMN_NAME, PKCOLUMN_NAME from DB.DBA.SYS_FOREIGN_KEYS
	    where FK_TABLE = tb and PK_TABLE = pkt order by KEY_SEQ do
	      {
		if (lastf <> FK_NAME)
		  {
		     if (fnam1 = fnam)
		       goto dro;
		     else
		       fnam1 := '';
		  }

                lastf := FK_NAME;
		fnam1 := concat (fnam1, FKCOLUMN_NAME, '_', PKCOLUMN_NAME);
	      }
dro:
	  --delete from DB.DBA.SYS_FOREIGN_KEYS where FK_TABLE = tb and PK_TABLE = pkt;
	  delete from DB.DBA.SYS_FOREIGN_KEYS where FK_TABLE = tb and 0 = casemode_strcmp (FK_NAME, lastf);
	  DB.DBA.ddl_fk_rules (pkt, null, null);
	  DB.DBA.ddl_fk_check_input (tb, 0);
	}
      else if (fkn <> 0)
	{
	  fkn := convert (varchar, fkn);
	  if (exists (select 1 from DB.DBA.SYS_FOREIGN_KEYS where FK_TABLE = tb and 0 = casemode_strcmp (FK_NAME, fkn)))
	    {
	      --for select PK_TABLE, FK_TABLE, FKCOLUMN_NAME
	      -- from DB.DBA.SYS_FOREIGN_KEYS where FK_TABLE = tb and 0 = casemode_strcmp (FK_NAME, fkn) do {
	      --  DB.DBA.ddl_fk_rules (PK_TABLE, FK_TABLE, FKCOLUMN_NAME);
	      --}
              pkt := (select distinct PK_TABLE from DB.DBA.SYS_FOREIGN_KEYS
		       where FK_TABLE = tb and 0 = casemode_strcmp (FK_NAME, fkn));
	      delete from DB.DBA.SYS_FOREIGN_KEYS where FK_TABLE = tb and 0 = casemode_strcmp (FK_NAME, fkn);
	      DB.DBA.ddl_fk_rules (pkt, null, null);
	      DB.DBA.ddl_fk_check_input (tb, 0);
	    }
	  else
	    signal ('42S12', sprintf ('Foreign key "%s" does not exists', fkn), 'SR298');
	}
      else
	signal ('37000', 'To drop foreign key should be specified NAME or REFERENCES', 'SR299');
    }
  else
    signal ('42S11', 'To modify a foreign key first drop the old and then add the new', 'SR300');
}
;

--!AWK PUBLIC
create procedure ddl_alter_constr (in tb varchar, in op integer, in decl any)
{
  declare type integer;
  declare orig_pkt varchar;
  tb := complete_table_name (tb, 1);
  ddl_owner_check (tb);
  --dbg_obj_print ('in ddl_alter_constr', decl);
  type := decl[0];
  if (op = 2 and length (decl) = 8 and type = 1 and 127 = __tag (aref (decl, 7)))
    {
      declare _name varchar;
      _name := convert (varchar, decl[7]);
      -- if it's a drop no constr body and there is a check constraint
      if (exists (select 1 from DB.DBA.SYS_CONSTRAINTS
       	where C_TABLE = tb and 0 = casemode_strcmp (C_TEXT, _name)))
	decl := vector (3, NULL, _name);
      else if (not exists (select 1 from DB.DBA.SYS_FOREIGN_KEYS
	where FK_TABLE = tb and 0 = casemode_strcmp (FK_NAME, _name)))
        decl[0] := 2;

      type := decl[0];
      if (type = 1)
	{
	  whenever not found goto next;
	  whenever sqlstate '*' goto next;
	  orig_pkt := null;
	  if (not isstring (decl[2]))
	    select PK_TABLE into orig_pkt from DB.DBA.SYS_FOREIGN_KEYS
	    where FK_TABLE = tb and 0 = casemode_strcmp (FK_NAME, _name);
	}
    }

  next:
  if (0 = type)
    {
      if (3 <> op)
	signal ('37000', 'A primary key cannot be added or dropped. It can only be modified. Use alter table .. modify primary key ...', 'SR301');
      ddl_pk_modify (tb, decl[3]);
    }
  else if (1 = type)
    {
      ddl_fk_modify (tb, op, decl);
    }
  else if (2 = type)
    ddl_unq_modify (tb, op, decl);
  else if (3 = type)
    {
      ddl_check_modify (tb, op, decl);
    }
  __REPL_DDL_FK_MODIFY_PROPAGATE (tb, op, decl, orig_pkt);
}
;

create procedure ddl_unq_modify (in tb varchar, in op integer, in decl any)
{
  declare nconstr, txt, cols_txt, stat, msg varchar;
  declare cols any;
  declare inx, len, int_name integer;

  int_name := 0;
  if (length (decl) = 8 and op = 2)
    nconstr := aref (decl, 7);
  else
    nconstr := aref (decl, 1);

  --dbg_obj_print (__tag (nconstr), decl);

  if (127 <> __tag (nconstr))
    {
      int_name := 1;
      nconstr := '';
    }
  else
    nconstr := convert (varchar, nconstr);

  txt := ''; cols_txt := ''; stat := '00000'; msg := ''; inx := 0;
  if (int_name or op = 1)
    {
      cols := aref (decl, 3);
      len := length (cols);
    }

  if (op = 1)
    {
      while (inx < len)
	{
	  cols_txt := concat (cols_txt, ',', aref (cols, inx));
	  if (int_name)
	    nconstr := concat (nconstr, '_',  aref (cols, inx));
	  inx := inx + 1;
	}
      if (int_name)
        {
	  nconstr := concat (name_part(tb,0), '_', name_part(tb, 1), '_', name_part (tb, 2), '_UNQC', nconstr);
          nconstr := DB.DBA.SYS_ALFANUM_NAME (nconstr);
        }
      cols_txt := substring (cols_txt, 2, length (cols_txt));
      txt := sprintf ('CREATE UNIQUE INDEX "%I" ON "%I"."%I"."%I" (%s)',
	       nconstr, name_part (tb, 0), name_part (tb, 1), name_part (tb, 2), cols_txt);
      if (exec (txt, stat, msg))
	signal (stat, msg);
    }
  else if (op = 2)
    {
      if (int_name)
	{
	  while (inx < len)
	    {
	      nconstr := concat (nconstr, '_',  aref (cols, inx));
	      inx := inx + 1;
	    }
	  nconstr := concat (name_part(tb,0), '_', name_part(tb, 1), '_', name_part (tb, 2), '_UNQC', nconstr);
          nconstr := DB.DBA.SYS_ALFANUM_NAME (nconstr);
	}
      if (not exists (select 1 from DB.DBA.SYS_KEYS where
	     0 = casemode_strcmp(KEY_TABLE, complete_table_name (tb, 0))
	    and 0 = casemode_strcmp (KEY_NAME, nconstr)
	    and KEY_IS_UNIQUE = 1))
	signal ('42S12', sprintf ('Constraint "%s" does not exists for table "%s"', nconstr, tb), 'SR320');

      txt := sprintf ('DROP INDEX "%I" "%I"."%I"."%I"',
	       nconstr, name_part (tb, 0), name_part (tb, 1), name_part (tb, 2));
      if (exec (txt, stat, msg))
	signal (stat, msg);
    }
  else
    signal ('37000', 'To modify a unique constraint first drop the old and then add the new', 'SR302');
}
;

create procedure ddl_check_modify (in tb varchar, in op integer, in decl any)
{
  declare constr_name varchar;
  declare constr_check any;

  constr_name := decl[2];
  constr_check := decl[1];

  --dbg_obj_print ('in ddl_check_modify', decl);
  if (op = 1)
    {
      declare cr cursor for
         select C_ID from DB.DBA.SYS_CONSTRAINTS where C_TABLE = tb order by C_TABLE, C_ID desc;
      declare last_id integer;

      if (isstring (constr_name))
	{
	  if (exists (select 1 from DB.DBA.SYS_CONSTRAINTS WHERE C_TABLE = tb and C_TEXT = constr_name))
	    signal ('22023', concat ('CHECK constraint ', constr_name, ' for table ', tb, ' already exists'),
	            'SR3634');
        }

      last_id := null;
	{
	  whenever not found goto notf;
	  open cr (exclusive, prefetch 1);
	  fetch cr into last_id;

	  notf:;
	}
      last_id := coalesce (last_id, -1) + 1;

      DDL_ENSURE_CONSTRAINT_NAME_UNIQUE (constr_name);
      insert into DB.DBA.SYS_CONSTRAINTS (C_TABLE, C_ID, C_TEXT, C_MODE)
        values (
	  tb,
	  last_id,
	  constr_name,
	  serialize (constr_check));
    }
  else if (op = 2)
    {
      if (isstring (constr_name))
	delete from DB.DBA.SYS_CONSTRAINTS where C_TABLE = tb and C_TEXT = constr_name;
      else
	delete from DB.DBA.SYS_CONSTRAINTS where C_TABLE = tb and blob_to_string (C_MODE) = serialize (constr_check);
    }
  else if (op = 3)
    {
      if (isstring (constr_name))
	update DB.DBA.SYS_CONSTRAINTS set C_MODE = serialize (constr_check) where C_TABLE = tb and C_TEXT = constr_name;
      else
	signal ('22023', 'Cannot MODIFY unnamed check constraints', 'SR365');
    }
  else
    signal ('22023', 'Invalid code in ALTER TABLE (CHECK constraint)', 'SR366');

  if (row_count () <> 1)
    {
      if (isstring (constr_name))
	signal ('22023', concat ('CHECK Constraint ', constr_name, ' on table ', tb, ' not defined'), 'SR367');
      else
	signal ('22023', concat ('unnamed CHECK Constraint on table ', tb, ' not defined'), 'SR368');
    }
  __ddl_read_constraints (tb);
}
;

create procedure __HTTP_XSLT (inout _XML any, inout DOC_URI varchar, inout XSLT_URI varchar, inout PARAMS any, inout MEDIATYPE varchar, inout ENC varchar)
{
  declare result any;
  declare _xslt_url varchar;
  if (XSLT_URI like 'precompiled:%')
    _xslt_url := substring (XSLT_URI, 13, length (XSLT_URI));
  else
    _xslt_url := WS.WS.EXPAND_URL (DOC_URI, XSLT_URI);
  if (isarray (PARAMS))
    result := xslt (_xslt_url, xml_tree_doc (xml_tree (_XML), DOC_URI), PARAMS);
  else
    result := xslt (_xslt_url, xml_tree_doc (xml_tree (_XML), DOC_URI));
  http_output_flush ();
  MEDIATYPE := xml_tree_doc_media_type(result);
  ENC := xml_tree_doc_encoding (result);
  http_value (result);
}
;


-- create triggers for consistency rules
create procedure DB.DBA.ddl_fk_rules (in pktb varchar, in drop_tb varchar, in drop_col varchar)
{
  declare stmt, set_cl, whe_cl, updst, delst, thetb, pkcols, pkvars, trig_pref, skip_on_this varchar;
  declare is_upd, is_del integer;

  is_upd := 0;
  is_del := 0;
  -- XXX: first build check input triggers
  DB.DBA.ddl_pk_check_input (pktb, drop_tb, drop_col);
  pktb := complete_table_name (pktb, 1);
  -- the table is dropped
  if (drop_tb is not null)
    drop_tb := complete_table_name (drop_tb, 1);
  else
    drop_tb := '';

  -- the column is dropped drop_tb = skip_on_this
  if (drop_col is null)
    {
      skip_on_this := '';
      drop_col := '';
    }
  else
    {
      skip_on_this := drop_tb;
      drop_tb := '';
    }
  pkcols := ''; pkvars := ''; thetb := ''; set_cl := ''; whe_cl := ''; updst := '';
  trig_pref := sprintf ('%s_%s_%s', DB.DBA.SYS_ALFANUM_NAME (name_part (pktb, 0)),
				    DB.DBA.SYS_ALFANUM_NAME (name_part (pktb, 1)),
				    DB.DBA.SYS_ALFANUM_NAME (name_part (pktb, 2)));
  --dbg_obj_print ('FK def: ', pktb, drop_tb, drop_col);
  for select distinct PKCOLUMN_NAME from DB.DBA.SYS_FOREIGN_KEYS
    where 0 = casemode_strcmp (PK_TABLE, pktb) and (UPDATE_RULE > 0 or DELETE_RULE > 0)
	  and 0 <> casemode_strcmp (FK_TABLE, drop_tb)
	  and not (0 = casemode_strcmp (FK_TABLE, skip_on_this) and 0 = casemode_strcmp (FKCOLUMN_NAME, drop_col))
	do
    {
      pkcols := concat (pkcols, '"', PKCOLUMN_NAME, '", ');
      pkvars := concat (pkvars, ' DECLARE _VAR_' , DB.DBA.SYS_ALFANUM_NAME (PKCOLUMN_NAME), ' VARCHAR; \n _VAR_',
		  DB.DBA.SYS_ALFANUM_NAME (PKCOLUMN_NAME), ' := O."', PKCOLUMN_NAME, '";\n');
    }
  if (length (pkcols) > 2)
    pkcols := substring (pkcols, 1, length (pkcols) - 2);
  else
    {
      --dbg_obj_print ('No pk cols exit.');
      if (exists (select 1 from DB.DBA.SYS_TRIGGERS where name_part (T_NAME, 2) = sprintf ('%s_FK_UPDATE', trig_pref)))
	{
	  stmt := sprintf ('DROP TRIGGER "%I"."%I"."%s_FK_UPDATE"', name_part (pktb, 0), name_part (pktb, 1), trig_pref);
	  DB.DBA.execstr (stmt);
	}
      if (exists (select 1 from DB.DBA.SYS_TRIGGERS where name_part (T_NAME, 2) = sprintf ('%s_FK_DELETE', trig_pref)))
	{
	  stmt := sprintf ('DROP TRIGGER "%I"."%I"."%s_FK_DELETE"', name_part (pktb, 0), name_part (pktb, 1), trig_pref);
	  DB.DBA.execstr (stmt);
	}
      return;
    }

  -- create update statements
  for select FK_TABLE, FKCOLUMN_NAME, PKCOLUMN_NAME, UPDATE_RULE  from DB.DBA.SYS_FOREIGN_KEYS
    where 0 = casemode_strcmp (PK_TABLE, pktb) and UPDATE_RULE is not null and UPDATE_RULE > 0
	and 0 <> casemode_strcmp (FK_TABLE, drop_tb)
	and not (0 = casemode_strcmp (FK_TABLE, skip_on_this) and 0 = casemode_strcmp (FKCOLUMN_NAME, drop_col))
	order by FK_TABLE do
      {

	is_upd := 1;
	if (FK_TABLE <> thetb and thetb <> '')
	  {
	    set_cl := substring (set_cl, 1, length (set_cl) - 2);
	    whe_cl := concat (' WHERE ', whe_cl);
	    whe_cl := substring (whe_cl, 1, length (whe_cl) - 5);
	    updst := concat (updst, sprintf ('  UPDATE "%I"."%I"."%I" SET ', name_part (thetb, 0),
			    name_part (thetb, 1), name_part (thetb, 2)), set_cl, whe_cl, ';\n');
	    set_cl := '';
	    whe_cl := '';
	  }
	if (FK_TABLE is not null)
	  {
	    thetb := FK_TABLE;
	    if (UPDATE_RULE = 1)
	      set_cl := concat (set_cl, sprintf ('"%I" = N."%I", ' , FKCOLUMN_NAME, PKCOLUMN_NAME));
	    else if (UPDATE_RULE = 2)
	      set_cl := concat (set_cl, sprintf ('"%I" = NULL, ' , FKCOLUMN_NAME));
	    else if (UPDATE_RULE = 3)
	      set_cl := concat (set_cl,
		  sprintf ('"%I" = coalesce ((select deserialize (COL_DEFAULT) from DB.DBA.SYS_COLS where "COLUMN" = ''%I'' and "TABLE" = ''%I''), NULL), ' ,
		    FKCOLUMN_NAME, FKCOLUMN_NAME, FK_TABLE));

	    whe_cl := concat (whe_cl, sprintf ('"%I" = O."%I" and ' , FKCOLUMN_NAME, PKCOLUMN_NAME));
	  }
      }
    if (thetb <> '' and set_cl <> '' and whe_cl <> '')
      {
	set_cl := substring (set_cl, 1, length (set_cl) - 2);
	whe_cl := concat (' WHERE ', whe_cl);
	whe_cl := substring (whe_cl, 1, length (whe_cl) - 5);
	updst := concat (updst, sprintf ('  UPDATE "%I"."%I"."%I" SET ', name_part (thetb, 0),
			name_part (thetb, 1), name_part (thetb, 2)), set_cl, whe_cl, ';\n');
	set_cl := '';
	whe_cl := '';
      }

  if (is_upd > 0)
    {
stmt := sprintf ('CREATE TRIGGER "%s_FK_UPDATE" AFTER UPDATE (%s)\n ON "%I"."%I"."%I" ORDER 99 REFERENCING OLD AS O, NEW AS N {\n DECLARE EXIT HANDLER FOR SQLSTATE \'*\' { ROLLBACK WORK; RESIGNAL; };\n %s \n }',
		    trig_pref, pkcols,
		    name_part (pktb, 0), name_part (pktb, 1), name_part (pktb, 3), updst);
      DB.DBA.execstr1 (stmt);
    }
  else if (exists (select 1 from DB.DBA.SYS_TRIGGERS where name_part (T_NAME, 2) = sprintf ('%s_FK_UPDATE', trig_pref)))
    {
--      dbg_obj_print ('No upd rule -> drop trg.');
      stmt := sprintf ('DROP TRIGGER "%I"."%I"."%s_FK_UPDATE"', name_part (pktb, 0), name_part (pktb, 1), trig_pref);
      DB.DBA.execstr (stmt);
    }
delst := ''; thetb := '';
  -- create delete statements
  for select FK_TABLE, FKCOLUMN_NAME, PKCOLUMN_NAME from DB.DBA.SYS_FOREIGN_KEYS
    where 0 = casemode_strcmp (PK_TABLE, pktb) and DELETE_RULE = 1
	and 0 <> casemode_strcmp (FK_TABLE, drop_tb)
	and not (0 = casemode_strcmp (FK_TABLE, skip_on_this) and 0 = casemode_strcmp (FKCOLUMN_NAME, drop_col))
	order by FK_TABLE do
      {
	is_del := 1;
	if (FK_TABLE <> thetb and thetb <> '')
	  {
	    whe_cl := concat (' WHERE ', whe_cl);
	    whe_cl := substring (whe_cl, 1, length (whe_cl) - 5);
	    delst := concat (delst, sprintf ('  DELETE FROM "%I"."%I"."%I" ', name_part (thetb, 0),
			    name_part (thetb, 1), name_part (thetb, 2)), whe_cl, ';\n');
	    whe_cl := '';
	  }
	if (FK_TABLE is not null)
	  {
	    thetb := FK_TABLE;
	    whe_cl := concat (whe_cl, sprintf ('"%I" = _VAR_%s and ' , FKCOLUMN_NAME, DB.DBA.SYS_ALFANUM_NAME (PKCOLUMN_NAME)));
	  }
      }
  if (thetb <> '' and whe_cl <> '')
    {
      whe_cl := concat (' WHERE ', whe_cl);
      whe_cl := substring (whe_cl, 1, length (whe_cl) - 5);
      delst := concat (delst, sprintf ('  DELETE FROM "%I"."%I"."%I" ', name_part (thetb, 0),
			name_part (thetb, 1), name_part (thetb, 2)), whe_cl, ';\n');
      set_cl := '';
      whe_cl := '';
    }
  -- create update after delete statements
  updst := '';  thetb := '';
  for select FK_TABLE, FKCOLUMN_NAME, PKCOLUMN_NAME, DELETE_RULE  from DB.DBA.SYS_FOREIGN_KEYS
    where 0 = casemode_strcmp (PK_TABLE, pktb) and DELETE_RULE is not null and DELETE_RULE > 1
	and 0 <> casemode_strcmp (FK_TABLE, drop_tb)
	and not (0 = casemode_strcmp (FK_TABLE, skip_on_this) and 0 = casemode_strcmp (FKCOLUMN_NAME, drop_col))
	order by FK_TABLE do
      {
	is_del := 1;
	if (FK_TABLE <> thetb and thetb <> '')
	  {
	    set_cl := substring (set_cl, 1, length (set_cl) - 2);
	    whe_cl := concat (' WHERE ', whe_cl);
	    whe_cl := substring (whe_cl, 1, length (whe_cl) - 5);
	    updst := concat (updst, sprintf ('  UPDATE "%I"."%I"."%I" SET ', name_part (thetb, 0),
			    name_part (thetb, 1), name_part (thetb, 2)), set_cl, whe_cl, ';\n');
	    set_cl := '';
	    whe_cl := '';
	  }
	if (FK_TABLE is not null)
	  {
	    thetb := FK_TABLE;
	    if (DELETE_RULE = 2)
	      set_cl := concat (set_cl, sprintf ('"%I" = NULL, ' , FKCOLUMN_NAME));
	    else if (DELETE_RULE = 3)
	      set_cl := concat (set_cl,
		  sprintf ('"%I" = coalesce ((select deserialize (COL_DEFAULT) from DB.DBA.SYS_COLS where "COLUMN" = ''%I'' and "TABLE" = ''%I''), NULL), ' ,
		    FKCOLUMN_NAME, FKCOLUMN_NAME, FK_TABLE));

	    whe_cl := concat (whe_cl, sprintf ('"%I" = _VAR_%s and ' , FKCOLUMN_NAME, DB.DBA.SYS_ALFANUM_NAME (PKCOLUMN_NAME)));
	  }
      }
    if (thetb <> '' and set_cl <> '' and whe_cl <> '')
      {
	set_cl := substring (set_cl, 1, length (set_cl) - 2);
	whe_cl := concat (' WHERE ', whe_cl);
	whe_cl := substring (whe_cl, 1, length (whe_cl) - 5);
	updst := concat (updst, sprintf ('  UPDATE "%I"."%I"."%I" SET ', name_part (thetb, 0),
			name_part (thetb, 1), name_part (thetb, 2)), set_cl, whe_cl, ';\n');
	set_cl := '';
	whe_cl := '';
      }

  if (is_del > 0)
    {
      stmt := sprintf ('CREATE TRIGGER "%s_FK_DELETE" AFTER DELETE \n ON "%I"."%I"."%I" ORDER 99 referencing old as O {\n DECLARE EXIT HANDLER FOR SQLSTATE \'*\' { ROLLBACK WORK; RESIGNAL; };\n %s %s %s \n}',
		    trig_pref, name_part (pktb, 0), name_part (pktb, 1), name_part (pktb, 3), pkvars, delst, updst);
      DB.DBA.execstr1 (stmt);
    }
  else if (exists (select 1 from DB.DBA.SYS_TRIGGERS where name_part (T_NAME, 2) = sprintf ('%s_FK_DELETE', trig_pref)))
    {
--      dbg_obj_print ('No delete rule -> drop trg.');
      stmt := sprintf ('DROP TRIGGER "%I"."%I"."%s_FK_DELETE"', name_part (pktb, 0), name_part (pktb, 1), trig_pref);
      DB.DBA.execstr (stmt);
    }
}
;

-- create triggers for input check of referenced columns from FK tables
create procedure DB.DBA.ddl_pk_check_input (in pktb varchar, in drop_tb varchar, in drop_col varchar)
{
  declare uniq, trig_pref, vars, whe, uwhe, stmt, ins, upd, fktb, skip_on_this, pku varchar;
  declare _u, _d, _uc, _dc integer;


vars := ''; whe := ''; uwhe := ''; ins := ''; upd := ''; pku := '';
  pktb := complete_table_name (pktb, 1);
  trig_pref := DB.DBA.SYS_ALFANUM_NAME (pktb);
  -- the table is dropped
  if (drop_tb is not null)
    drop_tb := complete_table_name (drop_tb, 1);
  else
    drop_tb := '';

  -- the column is dropped drop_tb = skip_on_this
  if (drop_col is null)
    {
      skip_on_this := '';
      drop_col := '';
    }
  else
    {
      skip_on_this := drop_tb;
      drop_tb := '';
    }

  _uc := 0; _dc := 0;
  for select distinct FK_TABLE as fk_table_name, FK_NAME as fkname from DB.DBA.SYS_FOREIGN_KEYS
    where 0 = casemode_strcmp (PK_TABLE, pktb)
     	and not (0 = casemode_strcmp (FK_TABLE, PK_TABLE) and 0 = casemode_strcmp (PKCOLUMN_NAME, FKCOLUMN_NAME))
	--and 0 <> casemode_strcmp (FK_TABLE, PK_TABLE) ### prevents self-referencing FK table
	do {

     fktb := complete_table_name (fk_table_name, 1);
     _u := 0; _d := 0;
     for select PKCOLUMN_NAME as pk_col_name, FKCOLUMN_NAME as fk_col_name, UPDATE_RULE, DELETE_RULE from DB.DBA.SYS_FOREIGN_KEYS
       where 0 = casemode_strcmp (PK_TABLE, pktb) and
	0 = casemode_strcmp (FK_TABLE, fk_table_name)
	and 0 <> casemode_strcmp (FK_TABLE, drop_tb)
	and FK_NAME = fkname
	and not (0 = casemode_strcmp (FK_TABLE, skip_on_this) and 0 = casemode_strcmp (FKCOLUMN_NAME, drop_col))
	do
	  {
	    if (UPDATE_RULE = 0)
	      {
		uwhe := concat (uwhe, '"', fk_col_name, '" = O."', pk_col_name, '" and ');
		pku := concat (pku, 'N."', pk_col_name, '" <> O."', pk_col_name, '" or ');
		_u := 1;
		_uc := _uc + 1;
	      }

	    if (DELETE_RULE = 0)
	      {
		vars := concat (vars, '\n DECLARE _VAR_', DB.DBA.SYS_ALFANUM_NAME (pk_col_name), ' ANY;\n _VAR_',
			DB.DBA.SYS_ALFANUM_NAME (pk_col_name), sprintf (' := O."%I"', pk_col_name), ';\n');
		whe := concat (whe, '"', fk_col_name, '" = _VAR_', DB.DBA.SYS_ALFANUM_NAME (pk_col_name), ' and ');
		_d := 1;
		_dc := _dc + 1;
	      }
	  }

    if (_d)
      {
	whe := substring (whe, 1, length (whe) - 5);
	ins := concat (ins, ' { ', vars, sprintf ('if (exists (select 1 from "%I"."%I"."%I"',
	      name_part (fk_table_name, 0), name_part (fk_table_name, 1), name_part (fk_table_name,2)),
	      ' WHERE ', whe, ')) \n',
	      sprintf ('signal (''S1000'',''DELETE statement conflicted with COLUMN REFERENCE constraint "%s"'', ''SR304'');\n', fkname), ' } ');
      }

    if (_u)
      {
	uwhe := substring (uwhe, 1, length (uwhe) - 5);
	pku := concat ('(', substring (pku, 1, length (pku) - 4), ') and ');

	upd := concat (upd, sprintf ('if (%s exists (select 1 from "%I"."%I"."%I"', pku,
	      name_part (fktb, 0), name_part (fktb, 1), name_part (fktb,2)), ' WHERE ', uwhe, ')) \n',
	       sprintf ('signal (''S1000'',''UPDATE statement conflicted with COLUMN REFERENCE constraint "%s"'', ''SR305'');\n', fkname));
      }
    vars := ''; whe := ''; uwhe := ''; pku := '';
  }

  --dbg_obj_print (_uc, _dc);
  if (_dc > 0)
    {
      stmt := concat ('CREATE TRIGGER ', upper (trig_pref),
      sprintf ('_PK_CHECK_DELETE BEFORE DELETE ON "%I"."%I"."%I" order 99 referencing old as O {\n if (''ON'' <> registry_get (''FK_UNIQUE_CHEK''))\n\t return;\n', name_part (pktb, 0), name_part (pktb, 1), name_part (pktb,2)), ins, '\n}\n');
      DB.DBA.execstr1 (stmt);
      --dbg_obj_print ('del trig: \n', stmt);
    }
  else if (exists (select 1 from DB.DBA.SYS_TRIGGERS where name_part (T_NAME, 2) = concat (upper (trig_pref), '_PK_CHECK_DELETE')))
    {
      stmt := concat (sprintf ('DROP TRIGGER "%I"."%I".', name_part (pktb, 0), name_part (pktb, 1)), upper (trig_pref), '_PK_CHECK_DELETE');
      DB.DBA.execstr (stmt);
    }

  if (_uc > 0)
    {
      stmt := concat ('CREATE TRIGGER ', upper (trig_pref),
      sprintf ('_PK_CHECK_UPDATE BEFORE UPDATE ON "%I"."%I"."%I" order 99 REFERENCING OLD AS O, NEW AS N {\n if (''ON'' <> registry_get (''FK_UNIQUE_CHEK''))\n\t return;\n',
      name_part (pktb, 0), name_part (pktb, 1), name_part (pktb,2)), upd, '\n}\n');
      --dbg_obj_print ('upd trig: \n', stmt);
      DB.DBA.execstr1 (stmt);
    }
  else if (exists (select 1 from DB.DBA.SYS_TRIGGERS where name_part (T_NAME, 2) = concat (upper (trig_pref), '_PK_CHECK_UPDATE')))
    {
      stmt := concat (sprintf ('DROP TRIGGER "%I"."%I".', name_part (pktb, 0), name_part (pktb, 1)), upper (trig_pref), '_PK_CHECK_UPDATE');
      DB.DBA.execstr (stmt);
    }
}
;


create procedure execstr1 (in str varchar)
{
  declare st, msg varchar;
  st := '00000';
  __set_user_id ('dba');
  exec (str, st, msg, vector (), 0, null, null);
  __pop_user_id ();
  if (st <> '00000')
    {
      txn_error (6);
      signal (st, msg);
    }
}
;



-- create triggers for input check of referenced columns
create procedure DB.DBA.ddl_fk_check_input (in fktb varchar, in to_drop integer)
{
  declare uniq, trig_pref, vars, whe, uwhe, stmt, ins, upd, pktb, nself, uself varchar;

  vars := ''; whe := ''; uwhe := ''; ins := ''; upd := '';
  fktb := complete_table_name (fktb, 1);
  trig_pref := SYS_ALFANUM_NAME (fktb);

  if (to_drop = 1)
    {
      if (exists (select 1 from DB.DBA.SYS_TRIGGERS where name_part (T_NAME, 2) = concat (upper (trig_pref), '_FK_CHECK_UPDATE')))
	{
	  stmt := concat (sprintf ('DROP TRIGGER "%I"."%I".', name_part (fktb, 0), name_part (fktb, 1)), upper (trig_pref), '_FK_CHECK_UPDATE');
	  DB.DBA.execstr (stmt);
	  stmt := concat (sprintf ('DROP TRIGGER "%I"."%I".', name_part (fktb, 0), name_part (fktb, 1)), upper (trig_pref), '_FK_CHECK_INSERT');
	  DB.DBA.execstr (stmt);
	}
       return;
    }

  to_drop := 1;

  declare ncond, uncond	varchar;
  ncond := ''; uncond := ''; nself := ''; uself := '';
  for select distinct PK_TABLE as pk_table_name, FK_NAME as fkname from DB.DBA.SYS_FOREIGN_KEYS
    where 0 = casemode_strcmp (FK_TABLE, fktb)
     	and not (0 = casemode_strcmp (FK_TABLE, PK_TABLE) and 0 = casemode_strcmp (PKCOLUMN_NAME, FKCOLUMN_NAME))
	--and 0 <> casemode_strcmp (FK_TABLE, PK_TABLE) ### prevents self-referencing FK table
    do {
     pktb := complete_table_name (pk_table_name, 1);
     for select PKCOLUMN_NAME as pk_col_name, FKCOLUMN_NAME as fk_col_name from DB.DBA.SYS_FOREIGN_KEYS
       where 0 = casemode_strcmp (FK_TABLE, fktb) and
	0 = casemode_strcmp (PK_TABLE, pk_table_name) and FK_NAME = fkname do
       {
	vars := concat (vars, '\n DECLARE _VAR_', DB.DBA.SYS_ALFANUM_NAME (fk_col_name), ' ANY;\n _VAR_',
		DB.DBA.SYS_ALFANUM_NAME (fk_col_name), sprintf (' := N."%I"', fk_col_name), ';\n');
	whe := concat (whe, '"', pk_col_name, '" = _VAR_', DB.DBA.SYS_ALFANUM_NAME (fk_col_name), ' and ');
	uwhe := concat (uwhe, '"', pk_col_name, '" = N."', fk_col_name, '" and ');
	ncond := concat (ncond, sprintf ('_VAR_%s IS NOT NULL', DB.DBA.SYS_ALFANUM_NAME (fk_col_name)), ' and ');
	uncond := concat (uncond, sprintf ('N."%I" IS NOT NULL', fk_col_name), ' and ');
	if (0 = casemode_strcmp (fktb, pk_table_name))
	  {
	    nself := concat (nself, ' N."', fk_col_name, '" <> N."', pk_col_name, '" and ');
	    uself := concat (uself, ' N."', fk_col_name, '" <> N."', pk_col_name, '" and ');
	  }
       }
    whe := substring (whe, 1, length (whe) - 5);
    uwhe := substring (uwhe, 1, length (uwhe) - 5);

    ins := concat (ins, vars, sprintf ('if (%s %s not exists (select 1 from "%I"."%I"."%I"',
	      ncond, nself, name_part (pk_table_name, 0), name_part (pk_table_name, 1), name_part (pk_table_name,2)),
	      ' WHERE ', whe, ')) \n',
	      sprintf ('signal (''S1000'',''INSERT statement conflicted with FOREIGN KEY constraint referencing table "%s"'', ''SR306'');\n', pk_table_name));
    upd := concat (upd, sprintf ('if (%s %s not exists (select 1 from "%I"."%I"."%I"',
	      uncond, uself, name_part (pktb, 0), name_part (pktb, 1), name_part (pktb,2)), ' WHERE ', uwhe, ')) \n',
	      sprintf ('signal (''S1000'',''UPDATE statement conflicted with FOREIGN KEY constraint referencing table "%s"'', ''SR307'');\n', pk_table_name));
vars := ''; whe := ''; uwhe := ''; ncond := ''; uncond := '';
    to_drop := 0;
  }

  if (to_drop = 1)
    {
      if (exists (select 1 from DB.DBA.SYS_TRIGGERS where name_part (T_NAME, 2) = concat (upper (trig_pref), '_FK_CHECK_UPDATE')))
	{
	  stmt := concat (sprintf ('DROP TRIGGER "%I"."%I".', name_part (fktb, 0), name_part (fktb, 1)), upper (trig_pref), '_FK_CHECK_UPDATE');
	  DB.DBA.execstr (stmt);
	  stmt := concat (sprintf ('DROP TRIGGER "%I"."%I".', name_part (fktb, 0), name_part (fktb, 1)), upper (trig_pref), '_FK_CHECK_INSERT');
	  DB.DBA.execstr (stmt);
	}
       return;
    }

  stmt := concat ('CREATE TRIGGER ', upper (trig_pref),
	    sprintf ('_FK_CHECK_INSERT before insert on "%I"."%I"."%I" order 99 referencing new as N { if (''ON'' <> registry_get (''FK_UNIQUE_CHEK'')) return;\n',
	      name_part (fktb, 0), name_part (fktb, 1), name_part (fktb,2)), ins, '\n}\n');
  DB.DBA.execstr1 (stmt);
  stmt := concat ('CREATE TRIGGER ', upper (trig_pref),
	    sprintf ('_FK_CHECK_UPDATE before update on "%I"."%I"."%I" order 99 REFERENCING OLD AS O, NEW AS N { if (''ON'' <> registry_get (''FK_UNIQUE_CHEK'')) return;\n',
	      name_part (fktb, 0), name_part (fktb, 1), name_part (fktb,2)), upd, '\n}\n');
  DB.DBA.execstr1 (stmt);
}
;

--#ifdef NEW_FTEXT_IN_SUBTABLES
--create procedure DB.DBA.col_check (in orig_tb varchar, in col varchar)
--{
--  if (not isstring (orig_tb) or not isstring (col))
--    signal ('22023', 'Function check_col needs strings as arguments', 'SR303');
--  declare _tb varchar;
--  declare _super varchar;
--  declare _subid integer;
--  declare _superid integer;
--  _tb := orig_tb;
--again:
--  for select "COLUMN" _col from DB.DBA.SYS_COLS
--     where 0 = casemode_strcmp ("TABLE", _tb) and 0 = casemode_strcmp ("COLUMN", col) do
--    {
--      return _col;
--    }
--  _subid := coalesce ((select KEY_ID from DB.DBA.SYS_KEYS where 0 = casemode_strcmp (KEY_TABLE, _tb)), -1);
--  _superid := coalesce ((select SUPER from DB.DBA.SYS_KEY_SUBKEY where SUB = _subid), -1);
--  _super := coalesce ((select KEY_TABLE from DB.DBA.SYS_KEYS where KEY_ID = _superid), null);
--  if (_super is not null)
--    {
--      _tb := _super;
--      goto again;
--    }
--  signal ('42S22', sprintf ('The column ''%s'' is not defined in the table ''%s''', col, orig_tb), 'SR084');
--}
--;
--#else
create procedure DB.DBA.col_check (in tb varchar, in col varchar)
{
  if (not isstring (tb) or not isstring (col))
    signal ('22023', 'Function check_col needs string as argument', 'SR303');
  declare ret varchar;
  declare c cursor for select "COLUMN" from DB.DBA.SYS_COLS
      where 0 = casemode_strcmp ("TABLE", tb) and 0 = casemode_strcmp ("COLUMN", col);
  whenever not found goto err;
  open c (prefetch 1);
  fetch c into ret;
  close c;
  return ret;
err:;
  close c;
  signal ('42S22', sprintf ('The column "%s" is not defined in the given table', col), 'SR084');
}
;


-- Added new columns for schema in SYS_VT_INDEX (backward compatibility)

--!AFTER
alter table DB.DBA.SYS_VT_INDEX add VI_ID_CONSTR varchar
;

--!AFTER
alter table DB.DBA.SYS_VT_INDEX add VI_OFFBAND_COLS varchar
;

--!AFTER
alter table DB.DBA.SYS_VT_INDEX add VI_OPTIONS varchar
;

--!AFTER
alter table DB.DBA.SYS_VT_INDEX add VI_LANGUAGE varchar
;

--!AFTER
alter table DB.DBA.SYS_VT_INDEX add VI_ENCODING varchar
;


charset_define ('MIK', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x410\x411\x412\x413\x414\x415\x416\x417\x418\x419\x41A\x41B\x41C\x41D\x41E\x41F\x420\x421\x422\x423\x424\x425\x426\x427\x428\x429\x42A\x42B\x42C\x42D\x42E\x42F\x430\x431\x432\x433\x434\x435\x436\x437\x438\x439\x43A\x43B\x43C\x43D\x43E\x43F\x440\x441\x442\x443\x444\x445\x446\x447\x448\x449\x44A\x44B\x44C\x44D\x44E\x44F\x2514\x2534\x252C\x251C\x2500\x253C\x2563\x2551\x255A\x2554\x2569\x2566\x2560\x2550\x256C\x2510\x2591\x2592\x2593\x2502\x2524\x2116\xA7\x2557\x255D\x2518\x250C\x2588\x2584\x258C\x2590\x2580\x3B1\x3B2\x393\x3C0\x3A3\x3C3\x3BC\x3C4\x3A6\x398\x3A9\x3B4\x221E\x2205\x2208\x2229\x2261\xB1\x2265\x2264\x2320\x2321\xF7\x2248\xB0\x2219\xB7\x221A\x207F\xB2\x25A0\xA0', vector ('999', 'CP999'))
;

charset_define ('WINDOWS-1250', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x20AC\x81\x201A\x83\x201E\x2026\x2020\x2021\x88\x2030\x160\x2039\x15A\x164\x17D\x179\x90\x2018\x2019\x201C\x201D\x2022\x2013\x2014\x98\x2122\x161\x203A\x15B\x165\x17E\x17A\xA0\x2C7\x2D8\x141\xA4\x104\xA6\xA7\xA8\xA9\x15E\xAB\xAC\xAD\xAE\x17B\xB0\xB1\x2DB\x142\xB4\xB5\xB6\xB7\xB8\x105\x15F\xBB\x13D\x2DD\x13E\x17C\x154\xC1\xC2\x102\xC4\x139\x106\xC7\x10C\xC9\x118\xCB\x11A\xCD\xCE\x10E\x110\x143\x147\xD3\xD4\x150\xD6\xD7\x158\x16E\xDA\x170\xDC\xDD\x162\xDF\x155\xE1\xE2\x103\xE4\x13A\x107\xE7\x10D\xE9\x119\xEB\x11B\xED\xEE\x10F\x111\x144\x148\xF3\xF4\x151\xF6\xF7\x159\x16F\xFA\x171\xFC\xFD\x163\x2D9', vector ('CP1250', 'MS-EE'))
;

charset_define ('WINDOWS-1251', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x402\x403\x201A\x453\x201E\x2026\x2020\x2021\x20AC\x2030\x409\x2039\x40A\x40C\x40B\x40F\x452\x2018\x2019\x201C\x201D\x2022\x2013\x2014\x98\x2122\x459\x203A\x45A\x45C\x45B\x45F\xA0\x40E\x45E\x408\xA4\x490\xA6\xA7\x401\xA9\x404\xAB\xAC\xAD\xAE\x407\xB0\xB1\x406\x456\x491\xB5\xB6\xB7\x451\x2116\x454\xBB\x458\x405\x455\x457\x410\x411\x412\x413\x414\x415\x416\x417\x418\x419\x41A\x41B\x41C\x41D\x41E\x41F\x420\x421\x422\x423\x424\x425\x426\x427\x428\x429\x42A\x42B\x42C\x42D\x42E\x42F\x430\x431\x432\x433\x434\x435\x436\x437\x438\x439\x43A\x43B\x43C\x43D\x43E\x43F\x440\x441\x442\x443\x444\x445\x446\x447\x448\x449\x44A\x44B\x44C\x44D\x44E\x44F', vector ('CP1251', 'MS-CYRL'))
;

charset_define ('WINDOWS-1252', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x20AC\x81\x201A\x192\x201E\x2026\x2020\x2021\x2C6\x2030\x160\x2039\x152\x8D\x17D\x8F\x90\x2018\x2019\x201C\x201D\x2022\x2013\x2014\x2DC\x2122\x161\x203A\x153\x9D\x17E\x178\xA0\xA1\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\xAC\xAD\xAE\xAF\xB0\xB1\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xBB\xBC\xBD\xBE\xBF\xC0\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xCB\xCC\xCD\xCE\xCF\xD0\xD1\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xDB\xDC\xDD\xDE\xDF\xE0\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xEB\xEC\xED\xEE\xEF\xF0\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFB\xFC\xFD\xFE\xFF', vector ('CP1252', 'MS-ANSI'))
;

charset_define ('WINDOWS-1257', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x20AC\x81\x201A\x83\x201E\x2026\x2020\x2021\x88\x2030\x8A\x2039\x8C\xA8\x2C7\xB8\x90\x2018\x2019\x201C\x201D\x2022\x2013\x2014\x98\x2122\x9A\x203A\x9C\xAF\x2DB\x9F\xA0\xA1\xA2\xA3\xA4\xA5\xA6\xA7\xD8\xA9\x156\xAB\xAC\xAD\xAE\xC6\xB0\xB1\xB2\xB3\xB4\xB5\xB6\xB7\xF8\xB9\x157\xBB\xBC\xBD\xBE\xE6\x104\x12E\x100\x106\xC4\xC5\x118\x112\x10C\xC9\x179\x116\x122\x136\x12A\x13B\x160\x143\x145\xD3\x14C\xD5\xD6\xD7\x172\x141\x15A\x16A\xDC\x17B\x17D\xDF\x105\x12F\x101\x107\xE4\xE5\x119\x113\x10D\xE9\x17A\x117\x123\x137\x12B\x13C\x161\x144\x146\xF3\x14D\xF5\xF6\xF7\x173\x142\x15B\x16B\xFC\x17C\x17E\x2D9', vector ('CP1257', 'WINBALTRIM'))
;

charset_define ('IBM437', N'\x263A\x263B\x2665\x2666\x2663\x2660\x2022\x25D8\x25E6\x25D9\x2642\x2640\x266A\x266B\x263C\x25B6\x25C0\x2195\x203C\xB6\xA7\x25AC\x21A8\x2191\x2193\x2192\x2190\x2310\x2194\x25B2\x25BC\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\xC7\xFC\xE9\xE2\xE4\xE0\xE5\xE7\xEA\xEB\xE8\xEF\xEE\xEC\xC4\xC5\xC9\xE6\xC6\xF4\xF6\xF2\xFB\xF9\xFF\xD6\xDC\xA2\xA3\xA5\x20A7\x192\xE1\xED\xF3\xFA\xF1\xD1\xAA\xBA\xBF\x2310\xAC\xBD\xBC\xA1\xAB\xBB\x2591\x2592\x2593\x2502\x2524\x2561\x2562\x2556\x2555\x2563\x2551\x2557\x255D\x255C\x255B\x2510\x2514\x2534\x252C\x251C\x2500\x253C\x255E\x255F\x255A\x2554\x2569\x2566\x2560\x2550\x256C\x2567\x2568\x2564\x2565\x2559\x2558\x2552\x2553\x256B\x256A\x2518\x250C\x2588\x2584\x258C\x2590\x2580\x3B1\x3B2\x393\x3C0\x3A3\x3C3\x3BC\x3C4\x3A6\x398\x3A9\x3B4\x221E\x2205\x2208\x2229\x2261\xB1\x2265\x2264\x2320\x2321\xF7\x2248\xB0\x2219\xB7\x221A\x207F\xB2\x25A0\xA0', vector ('CP437', '437', 'CSPC8CODEPAGE437'))
;

charset_define ('IBM850', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\xC7\xFC\xE9\xE2\xE4\xE0\xE5\xE7\xEA\xEB\xE8\xEF\xEE\xEC\xC4\xC5\xC9\xE6\xC6\xF4\xF6\xF2\xFB\xF9\xFF\xD6\xDC\xF8\xA3\xD8\xD7\x192\xE1\xED\xF3\xFA\xF1\xD1\xAA\xBA\xBF\xAE\xAC\xBD\xBC\xA1\xAB\xBB\x2591\x2592\x2593\x2502\x2524\xC1\xC2\xC0\xA9\x2563\x2551\x2557\x255D\xA2\xA5\x2510\x2514\x2534\x252C\x251C\x2500\x253C\xE3\xC3\x255A\x2554\x2569\x2566\x2560\x2550\x256C\xA4\xF0\xD0\xCA\xCB\xC8\x131\xCD\xCE\xCF\x2518\x250C\x2588\x2584\xA6\xCC\x2580\xD3\xDF\xD4\xD2\xF5\xD5\xB5\xFE\xDE\xDA\xDB\xD9\xFD\xDD\xAF\xB4\xAD\xB1\x2017\xBE\xB6\xA7\xF7\xB8\xB0\xA8\xB7\xB9\xB3\xB2\x25A0\xA0', vector ('CP850', '850', 'CSPC850MULTILINGUAL'))
;

charset_define ('IBM852', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\xC7\xFC\xE9\xE2\xE4\x16F\x107\xE7\x142\xEB\x150\x151\xEE\x179\xC4\x106\xC9\x139\x13A\xF4\xF6\x13D\x13E\x15A\x15B\xD6\xDC\x164\x165\x141\xD7\x10D\xE1\xED\xF3\xFA\x104\x105\x17D\x17E\x118\x119\xAC\x17A\x10C\x15F\xAB\xBB\x2591\x2592\x2593\x2502\x2524\xC1\xC2\x11A\x15E\x2563\x2551\x2557\x255D\x17B\x17C\x2510\x2514\x2534\x252C\x251C\x2500\x253C\x102\x103\x255A\x2554\x2569\x2566\x2560\x2550\x256C\xA4\x111\x110\x10E\xCB\x10F\x147\xCD\xCE\x11B\x2518\x250C\x2588\x2584\x162\x16E\x2580\xD3\xDF\xD4\x143\x144\x148\x160\x161\x154\xDA\x155\x170\xFD\xDD\x163\xB4\xAD\x2DD\x2DB\x2C7\x2D8\xA7\xF7\xB8\xB0\xA8\x2D9\x171\x158\x159\x25A0\xA0', vector ('CP852', '852', 'CSPCP852'))
;

charset_define ('IBM855', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x452\x402\x453\x403\x451\x401\x454\x404\x455\x405\x456\x406\x457\x407\x458\x408\x459\x409\x45A\x40A\x45B\x40B\x45C\x40C\x45E\x40E\x45F\x40F\x44E\x42E\x44A\x42A\x430\x410\x431\x411\x446\x426\x434\x414\x435\x415\x444\x424\x433\x413\xAB\xBB\x2591\x2592\x2593\x2502\x2524\x445\x425\x438\x418\x2563\x2551\x2557\x255D\x439\x419\x2510\x2514\x2534\x252C\x251C\x2500\x253C\x43A\x41A\x255A\x2554\x2569\x2566\x2560\x2550\x256C\xA4\x43B\x41B\x43C\x41C\x43D\x41D\x43E\x41E\x43F\x2518\x250C\x2588\x2584\x41F\x44F\x2580\x42F\x440\x420\x441\x421\x442\x422\x443\x423\x436\x416\x432\x412\x44C\x42C\x2116\xAD\x44B\x42B\x437\x417\x448\x428\x44D\x42D\x449\x429\x447\x427\xA7\x25A0\xA0', vector ('CP855', '855', 'CSIBM855'))
;

charset_define ('IBM866', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x410\x411\x412\x413\x414\x415\x416\x417\x418\x419\x41A\x41B\x41C\x41D\x41E\x41F\x420\x421\x422\x423\x424\x425\x426\x427\x428\x429\x42A\x42B\x42C\x42D\x42E\x42F\x430\x431\x432\x433\x434\x435\x436\x437\x438\x439\x43A\x43B\x43C\x43D\x43E\x43F\x2591\x2592\x2593\x2502\x2524\x2561\x2562\x2556\x2555\x2563\x2551\x2557\x255D\x255C\x255B\x2510\x2514\x2534\x252C\x251C\x2500\x253C\x255E\x255F\x255A\x2554\x2569\x2566\x2560\x2550\x256C\x2567\x2568\x2564\x2565\x2559\x2558\x2552\x2553\x256B\x256A\x2518\x250C\x2588\x2584\x258C\x2590\x2580\x440\x441\x442\x443\x444\x445\x446\x447\x448\x449\x44A\x44B\x44C\x44D\x44E\x44F\x401\x451\x404\x454\x407\x457\x40E\x45E\xB0\x2022\xB7\x221A\x2116\xA4\x25A0\xA0', vector ('CP866', '866', 'CSIBM866'))
;

charset_define ('IBM874', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x20AC\x81\x82\x83\x84\x2026\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x2018\x2019\x201C\x201D\x2022\x2013\x2014\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\xE01\xE02\xE03\xE04\xE05\xE06\xE07\xE08\xE09\xE0A\xE0B\xE0C\xE0D\xE0E\xE0F\xE10\xE11\xE12\xE13\xE14\xE15\xE16\xE17\xE18\xE19\xE1A\xE1B\xE1C\xE1D\xE1E\xE1F\xE20\xE21\xE22\xE23\xE24\xE25\xE26\xE27\xE28\xE29\xE2A\xE2B\xE2C\xE2D\xE2E\xE2F\xE30\xE31\xE32\xE33\xE34\xE35\xE36\xE37\xE38\xE39\xE3A\xDB\xDC\xDD\xDE\xE3F\xE40\xE41\xE42\xE43\xE44\xE45\xE46\xE47\xE48\xE49\xE4A\xE4B\xE4C\xE4D\xE4E\xE4F\xE50\xE51\xE52\xE53\xE54\xE55\xE56\xE57\xE58\xE59\xE5A\xE5B\xFC\xFD\xFE\xFF', vector ('CP874', '874'))
;

charset_define ('GOST19768-87', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\xA4\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\x401\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\xAC\xAD\xAE\xAF\x410\x411\x412\x413\x414\x415\x416\x417\x418\x419\x41A\x41B\x41C\x41D\x41E\x41F\x420\x421\x422\x423\x424\x425\x426\x427\x428\x429\x42A\x42B\x42C\x42D\x42E\x42F\x430\x431\x432\x433\x434\x435\x436\x437\x438\x439\x43A\x43B\x43C\x43D\x43E\x43F\x440\x441\x442\x443\x444\x445\x446\x447\x448\x449\x44A\x44B\x44C\x44D\x44E\x44F\xF0\x451\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFB\xFC\xFD\xFE\xFF', NULL)
;

charset_define ('ISO-8859-1', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\xA1\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\xAC\xAD\xAE\xAF\xB0\xB1\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xBB\xBC\xBD\xBE\xBF\xC0\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xCB\xCC\xCD\xCE\xCF\xD0\xD1\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xDB\xDC\xDD\xDE\xDF\xE0\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xEB\xEC\xED\xEE\xEF\xF0\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFB\xFC\xFD\xFE\xFF', vector ('ISO_8859-1', 'ISO_8859-1:1987', 'ISO-IR-100', 'LATIN1', 'L1', 'IBM819', 'CP819', '819', 'CSISOLATIN1'))
;

charset_define ('ISO-8859-10', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\x104\x112\x122\x12A\x128\x136\xA7\x13B\x110\x160\x166\x17D\xAD\x16A\x14A\xB0\x105\x113\x123\x12B\x129\x137\xB7\x13C\x111\x161\x167\x17E\x2015\x16B\x14B\x100\xC1\xC2\xC3\xC4\xC5\xC6\x12E\x10C\xC9\x118\xCB\x116\xCD\xCE\xCF\xD0\x145\x14C\xD3\xD4\xD5\xD6\x168\xD8\x172\xDA\xDB\xDC\xDD\xDE\xDF\x101\xE1\xE2\xE3\xE4\xE5\xE6\x12F\x10D\xE9\x119\xEB\x117\xED\xEE\xEF\xF0\x146\x14D\xF3\xF4\xF5\xF6\x169\xF8\x173\xFA\xFB\xFC\xFD\xFE\x138', vector ('ISO_8859-10', 'ISO_8859-10:1992', 'ISO-IR-157', 'L6', 'LATIN6', 'CSISOLATIN6'))
;

charset_define ('ISO-8859-11', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\xE01\xE02\xE03\xE04\xE05\xE06\xE07\xE08\xE09\xE0A\xE0B\xE0C\xE0D\xE0E\xE0F\xE10\xE11\xE12\xE13\xE14\xE15\xE16\xE17\xE18\xE19\xE1A\xE1B\xE1C\xE1D\xE1E\xE1F\xE20\xE21\xE22\xE23\xE24\xE25\xE26\xE27\xE28\xE29\xE2A\xE2B\xE2C\xE2D\xE2E\xE2F\xE30\xE31\xE32\xE33\xE34\xE35\xE36\xE37\xE38\xE39\xE3A\xDB\xDC\xDD\xDE\xE3F\xE40\xE41\xE42\xE43\xE44\xE45\xE46\xE47\xE48\xE49\xE4A\xE4B\xE4C\xE4D\xE4E\xE4F\xE50\xE51\xE52\xE53\xE54\xE55\xE56\xE57\xE58\xE59\xE5A\xE5B\xFC\xFD\xFE\xFF', vector ('ISO_8859-11'))
;

charset_define ('ISO-8859-13', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\x201D\xA2\xA3\xA4\x201E\xA6\xA7\xD8\xA9\x156\xAB\xAC\xAD\xAE\xC6\xB0\xB1\xB2\xB3\x201C\xB5\xB6\xB7\xF8\xB9\x157\xBB\xBC\xBD\xBE\xE6\x104\x12E\x100\x106\xC4\xC5\x118\x112\x10C\xC9\x179\x116\x122\x136\x12A\x13B\x160\x143\x145\xD3\x14C\xD5\xD6\xD7\x172\x141\x15A\x16A\xDC\x17B\x17D\xDF\x105\x12F\x101\x107\xE4\xE5\x119\x113\x10D\xE9\x17A\x117\x123\x137\x12B\x13C\x161\x144\x146\xF3\x14D\xF5\xF6\xF7\x173\x142\x15B\x16B\xFC\x17C\x17E\x2019', vector ('ISO_8859-13'))
;

charset_define ('ISO-8859-14', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\x1E02\x1E03\xA3\x10A\x10B\x1E0A\xA7\x1E80\xA9\x1E82\x1E0B\x1EF2\xAD\xAE\x178\x1E1E\x1E1F\x120\x121\x1E40\x1E41\xB6\x1E56\x1E81\x1E57\x1E83\x1E60\x1EF3\x1E84\x1E85\x1E61\xC0\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xCB\xCC\xCD\xCE\xCF\x174\xD1\xD2\xD3\xD4\xD5\xD6\x1E6A\xD8\xD9\xDA\xDB\xDC\xDD\x176\xDF\xE0\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xEB\xEC\xED\xEE\xEF\x175\xF1\xF2\xF3\xF4\xF5\xF6\x1E6B\xF8\xF9\xFA\xFB\xFC\xFD\x177\xFF', vector ('ISO_8859-14', 'ISO_8859-14:1998', 'LATIN8', 'L8', 'ISO-CELTIC', 'ISO-IR-199'))
;

charset_define ('ISO-8859-15', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\xA1\xA2\xA3\x20AC\xA5\x160\xA7\x161\xA9\xAA\xAB\xAC\xAD\xAE\xAF\xB0\xB1\xB2\xB3\x17D\xB5\xB6\xB7\x17E\xB9\xBA\xBB\x152\x153\x178\xBF\xC0\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xCB\xCC\xCD\xCE\xCF\xD0\xD1\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xDB\xDC\xDD\xDE\xDF\xE0\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xEB\xEC\xED\xEE\xEF\xF0\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFB\xFC\xFD\xFE\xFF', vector ('ISO_8859-15'))
;

charset_define ('ISO-8859-2', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\x104\x2D8\x141\xA4\x13D\x15A\xA7\xA8\x160\x15E\x164\x179\xAD\x17D\x17B\xB0\x105\x2DB\x142\xB4\x13E\x15B\x2C7\xB8\x161\x15F\x165\x17A\x2DD\x17E\x17C\x154\xC1\xC2\x102\xC4\x139\x106\xC7\x10C\xC9\x118\xCB\x11A\xCD\xCE\x10E\x110\x143\x147\xD3\xD4\x150\xD6\xD7\x158\x16E\xDA\x170\xDC\xDD\x162\xDF\x155\xE1\xE2\x103\xE4\x13A\x107\xE7\x10D\xE9\x119\xEB\x11B\xED\xEE\x10F\x111\x144\x148\xF3\xF4\x151\xF6\xF7\x159\x16F\xFA\x171\xFC\xFD\x163\x2D9', vector ('ISO_8859-2', 'ISO_8859-2:1987', 'ISO-IR-101', 'LATIN2', 'L2', 'CSISOLATIN2'))
;

charset_define ('ISO-8859-3', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\x126\x2D8\xA3\xA4\xA5\x124\xA7\xA8\x130\x15E\x11E\x134\xAD\xAE\x17B\xB0\x127\xB2\xB3\xB4\xB5\x125\xB7\xB8\x131\x15F\x11F\x135\xBD\xBE\x17C\xC0\xC1\xC2\xC3\xC4\x10A\x108\xC7\xC8\xC9\xCA\xCB\xCC\xCD\xCE\xCF\xD0\xD1\xD2\xD3\xD4\x120\xD6\xD7\x11C\xD9\xDA\xDB\xDC\x16C\x15C\xDF\xE0\xE1\xE2\xE3\xE4\x10B\x109\xE7\xE8\xE9\xEA\xEB\xEC\xED\xEE\xEF\xF0\xF1\xF2\xF3\xF4\x121\xF6\xF7\x11D\xF9\xFA\xFB\xFC\x16D\x15D\x2D9', vector ('ISO_8859-3', 'ISO_8859-3:1988', 'ISO-IR-109', 'LATIN3', 'L3', 'CSISOLATIN3'))
;

charset_define ('ISO-8859-4', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\x104\x138\x156\xA4\x128\x13B\xA7\xA8\x160\x112\x122\x166\xAD\x17D\xAF\xB0\x105\x2DB\x157\xB4\x129\x13C\x2C7\xB8\x161\x113\x123\x167\x14A\x17E\x14B\x100\xC1\xC2\xC3\xC4\xC5\xC6\x12E\x10C\xC9\x118\xCB\x116\xCD\xCE\x12A\x110\x145\x14C\x136\xD4\xD5\xD6\xD7\xD8\x172\xDA\xDB\xDC\x168\x16A\xDF\x101\xE1\xE2\xE3\xE4\xE5\xE6\x12F\x10D\xE9\x119\xEB\x117\xED\xEE\x12B\x111\x146\x14D\x137\xF4\xF5\xF6\xF7\xF8\x173\xFA\xFB\xFC\x169\x16B\x2D9', vector ('ISO_8859-4', 'ISO-IR-110', 'LATIN4', 'L4', 'CSISOLATIN4', 'ISO_8859-4:1988'))
;

charset_define ('ISO-8859-5', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\x401\x402\x403\x404\x405\x406\x407\x408\x409\x40A\x40B\x40C\xAD\x40E\x40F\x410\x411\x412\x413\x414\x415\x416\x417\x418\x419\x41A\x41B\x41C\x41D\x41E\x41F\x420\x421\x422\x423\x424\x425\x426\x427\x428\x429\x42A\x42B\x42C\x42D\x42E\x42F\x430\x431\x432\x433\x434\x435\x436\x437\x438\x439\x43A\x43B\x43C\x43D\x43E\x43F\x440\x441\x442\x443\x444\x445\x446\x447\x448\x449\x44A\x44B\x44C\x44D\x44E\x44F\x2116\x451\x452\x453\x454\x455\x456\x457\x458\x459\x45A\x45B\x45C\xA7\x45E\x45F', vector ('ISO_8859-5', 'CYRILLIC', 'ISO-IR-144', 'CSISOLATINCYRILLIC', 'ISO_8859-5:1988'))
;

charset_define ('ISO-8859-6', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\xA1\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\x60C\xAD\xAE\xAF\xB0\xB1\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\x61B\xBC\xBD\xBE\x61F\xC0\x621\x622\x623\x624\x625\x626\x627\x628\x629\x62A\x62B\x62C\x62D\x62E\x62F\x630\x631\x632\x633\x634\x635\x636\x637\x638\x639\x63A\xDB\xDC\xDD\xDE\xDF\x640\x641\x642\x643\x644\x645\x646\x647\x648\x649\x64A\x64B\x64C\x64D\x64E\x64F\x650\x651\x652\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFB\xFC\xFD\xFE\xFF', vector ('ISO_8859-6', 'ARABIC', 'ISO-IR-127', 'ECMA-114', 'ASMO-708', 'CSISOLATINARABIC', 'ISO_8859-6:1987'))
;

charset_define ('ISO-8859-7', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\x2BD\x2BC\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\xAC\xAD\xAE\x2015\xB0\xB1\xB2\xB3\x384\x385\x386\xB7\x388\x389\x38A\xBB\x38C\xBD\x38E\x38F\x390\x391\x392\x393\x394\x395\x396\x397\x398\x399\x39A\x39B\x39C\x39D\x39E\x39F\x3A0\x3A1\xD2\x3A3\x3A4\x3A5\x3A6\x3A7\x3A8\x3A9\x3AA\x3AB\x3AC\x3AD\x3AE\x3AF\x3B0\x3B1\x3B2\x3B3\x3B4\x3B5\x3B6\x3B7\x3B8\x3B9\x3BA\x3BB\x3BC\x3BD\x3BE\x3BF\x3C0\x3C1\x3C2\x3C3\x3C4\x3C5\x3C6\x3C7\x3C8\x3C9\x3CA\x3CB\x3CC\x3CD\x3CE\xFF', vector ('ISO_8859-7', 'ISO_8859-7:1987', 'ISO-IR-126', 'ELOT_928', 'ECMA-118', 'GREEK', 'GREEK8', 'CSISOLATINGREEK'))
;

charset_define ('ISO-8859-8', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\xA1\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xD7\xAB\xAC\xAD\xAE\x203E\xB0\xB1\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xF7\xBB\xBC\xBD\xBE\xBF\xC0\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xCB\xCC\xCD\xCE\xCF\xD0\xD1\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xDB\xDC\xDD\xDE\x2017\x5D0\x5D1\x5D2\x5D3\x5D4\x5D5\x5D6\x5D7\x5D8\x5D9\x5DA\x5DB\x5DC\x5DD\x5DE\x5DF\x5E0\x5E1\x5E2\x5E3\x5E4\x5E5\x5E6\x5E7\x5E8\x5E9\x5EA\xFB\xFC\xFD\xFE\xFF', vector ('ISO_8859-8', 'ISO_8859-8:1988', 'ISO-IR-138', 'HEBREW', 'CSISOLATINHEBREW'))
;

charset_define ('ISO-8859-9', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\xA1\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\xAC\xAD\xAE\xAF\xB0\xB1\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xBB\xBC\xBD\xBE\xBF\xC0\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xCB\xCC\xCD\xCE\xCF\x11E\xD1\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xDB\xDC\x130\x15E\xDF\xE0\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xEB\xEC\xED\xEE\xEF\x11F\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFB\xFC\x131\x15F\xFF', vector ('ISO_8859-9', 'ISO_8859-9:1989', 'LATIN5', 'L5', 'ISO-IR-148', 'LATIN5', 'L5', 'CSISOLATIN5'))
;

charset_define ('KOI-0', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\xA4\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\xA1\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\xAC\xAD\xAE\xAF\xB0\xB1\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xBB\xBC\xBD\xBE\xBF\xC0\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xCB\xCC\xCD\xCE\xCF\xD0\xD1\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xDB\xDC\xDD\xDE\xDF\xE0\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xEB\xEC\xED\xEE\xEF\xF0\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFB\xFC\xFD\xFE\xFF', NULL)
;

charset_define ('KOI-7', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\xA4\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x42E\x410\x411\x426\x414\x415\x424\x413\x425\x418\x419\x41A\x41B\x41C\x41D\x41E\x41F\x42F\x420\x421\x422\x423\x416\x412\x42C\x42B\x417\x428\x42D\x429\x427\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\xA1\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\xAC\xAD\xAE\xAF\xB0\xB1\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xBB\xBC\xBD\xBE\xBF\xC0\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xCB\xCC\xCD\xCE\xCF\xD0\xD1\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xDB\xDC\xDD\xDE\xDF\xE0\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xEB\xEC\xED\xEE\xEF\xF0\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFB\xFC\xFD\xFE\xFF', NULL)
;

charset_define ('KOI8-A', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\xA4\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\xA1\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\xAC\xAD\xAE\xAF\xB0\xB1\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xBB\xBC\xBD\xBE\xBF\x44E\x430\x431\x446\x434\x435\x444\x433\x445\x438\x439\x43A\x43B\x43C\x43D\x43E\x43F\x44F\x440\x441\x442\x443\x436\x432\x44C\x44B\x437\x448\x44D\x449\x447\x44A\x42E\x410\x411\x426\x414\x415\x424\x413\x425\x418\x419\x41A\x41B\x41C\x41D\x41E\x41F\x42F\x420\x421\x422\x423\x416\x412\x42C\x42B\x417\x428\x42D\x429\x427\xFF', NULL)
;

charset_define ('KOI8-B', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\xA1\xA2\x451\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\xAC\xAD\xAE\xAF\xB0\xB1\xB2\x401\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xBB\xBC\xBD\xBE\xBF\x44E\x430\x431\x446\x434\x435\x444\x433\x445\x438\x439\x43A\x43B\x43C\x43D\x43E\x43F\x44F\x440\x441\x442\x443\x436\x432\x44C\x44B\x437\x448\x44D\x449\x447\x44A\x42E\x410\x411\x426\x414\x415\x424\x413\x425\x418\x419\x41A\x41B\x41C\x41D\x41E\x41F\x42F\x420\x421\x422\x423\x416\x412\x42C\x42B\x417\x428\x42D\x429\x427\x42A', NULL)
;

charset_define ('KOI8-E', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\x452\x453\x451\x454\x455\x456\x457\x458\x459\x45A\x45B\x45C\xAD\x45E\x45F\x2116\x402\x403\x401\x404\x405\x406\x407\x408\x409\x40A\x40B\x40C\xA4\x40E\x40F\x44E\x430\x431\x446\x434\x435\x444\x433\x445\x438\x439\x43A\x43B\x43C\x43D\x43E\x43F\x44F\x440\x441\x442\x443\x436\x432\x44C\x44B\x437\x448\x44D\x449\x447\x44A\x42E\x410\x411\x426\x414\x415\x424\x413\x425\x418\x419\x41A\x41B\x41C\x41D\x41E\x41F\x42F\x420\x421\x422\x423\x416\x412\x42C\x42B\x417\x428\x42D\x429\x427\x42A', NULL)
;

charset_define ('KOI8-F', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x2500\x2502\x250C\x2510\x2514\x2518\x251C\x2524\x252C\x2534\x253C\x2580\x2584\x2588\x258C\x2590\x2591\x2018\x2019\x201C\x201D\x2022\x2013\x2014\xA9\x2122\xA0\xBB\xAE\xAB\xB7\xA4\xA0\x452\x453\x451\x454\x455\x456\x457\x458\x459\x45A\x45B\x45C\x491\x45E\x45F\x2116\x402\x403\x401\x404\x405\x406\x407\x408\x409\x40A\x40B\x40C\x490\x40E\x40F\x44E\x430\x431\x446\x434\x435\x444\x433\x445\x438\x439\x43A\x43B\x43C\x43D\x43E\x43F\x44F\x440\x441\x442\x443\x436\x432\x44C\x44B\x437\x448\x44D\x449\x447\x44A\x42E\x410\x411\x426\x414\x415\x424\x413\x425\x418\x419\x41A\x41B\x41C\x41D\x41E\x41F\x42F\x420\x421\x422\x423\x416\x412\x42C\x42B\x417\x428\x42D\x429\x427\x42A', NULL)
;

charset_define ('KOI8-R', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x2500\x2502\x250C\x2510\x2514\x2518\x251C\x2524\x252C\x2534\x253C\x2580\x2584\x2588\x258C\x2590\x2591\x2592\x2593\x2320\x25A0\x2022\x221A\x2248\x2264\x2265\xA0\x2321\xB0\xB2\xB7\xF7\x2550\x2551\x2552\x451\x2553\x2554\x2555\x2556\x2557\x2558\x2559\x255A\x255B\x255C\x255D\x255E\x255F\x2560\x2561\x401\x2562\x2563\x2564\x2565\x2566\x2567\x2568\x2569\x256A\x256B\x256C\xA9\x44E\x430\x431\x446\x434\x435\x444\x433\x445\x438\x439\x43A\x43B\x43C\x43D\x43E\x43F\x44F\x440\x441\x442\x443\x436\x432\x44C\x44B\x437\x448\x44D\x449\x447\x44A\x42E\x410\x411\x426\x414\x415\x424\x413\x425\x418\x419\x41A\x41B\x41C\x41D\x41E\x41F\x42F\x420\x421\x422\x423\x416\x412\x42C\x42B\x417\x428\x42D\x429\x427\x42A', vector ('CSKOI8R'))
;

charset_define ('KOI8-U', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x2500\x2502\x250C\x2510\x2514\x2518\x251C\x2524\x252C\x2534\x253C\x2580\x2584\x2588\x258C\x2590\x2591\x2592\x2593\x2320\x25A0\x2022\x221A\x2248\x2264\x2265\xA0\x2321\xB0\xB2\xB7\xF7\x2550\x2551\x2552\x451\x454\x2554\x456\x457\x2557\x2558\x2559\x255A\x255B\x491\x255D\x255E\x255F\x2560\x2561\x401\x404\x2563\x406\x407\x2566\x2567\x2568\x2569\x256A\x490\x256C\xA9\x44E\x430\x431\x446\x434\x435\x444\x433\x445\x438\x439\x43A\x43B\x43C\x43D\x43E\x43F\x44F\x440\x441\x442\x443\x436\x432\x44C\x44B\x437\x448\x44D\x449\x447\x44A\x42E\x410\x411\x426\x414\x415\x424\x413\x425\x418\x419\x41A\x41B\x41C\x41D\x41E\x41F\x42F\x420\x421\x422\x423\x416\x412\x42C\x42B\x417\x428\x42D\x429\x427\x42A', NULL)
;

charset_define ('MAC-UKRAINIAN', N'\x1\x2\x3\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\xF\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x410\x411\x412\x413\x414\x415\x416\x417\x418\x419\x41A\x41B\x41C\x41D\x41E\x41F\x420\x421\x422\x423\x424\x425\x426\x427\x428\x429\x42A\x42B\x42C\x42D\x42E\x42F\x2020\xB0\x490\xA3\xA7\x2022\xB6\x406\xAE\xA9\x2122\x402\x452\x2260\x403\x453\x221E\xB1\x2264\x2265\x456\xB5\x491\x408\x404\x454\x407\x457\x409\x459\x40A\x45A\x458\x405\xAC\x221A\x192\x2248\x2206\xAB\xBB\x2026\xA0\x40B\x45B\x40C\x45C\x455\x2013\x2014\x201C\x201D\x2018\x2019\xF7\x201E\x40E\x45E\x40F\x45F\x2116\x401\x451\x44F\x430\x431\x432\x433\x434\x435\x436\x437\x438\x439\x43A\x43B\x43C\x43D\x43E\x43F\x440\x441\x442\x443\x444\x445\x446\x447\x448\x449\x44A\x44B\x44C\x44D\x44E\xA4', NULL)
;


create procedure
scheduler_init ()
{
  if (registry_get ('__scheduler_do_now__') = '1')
    registry_set ('__scheduler_do_now__', 'c');
  else
    registry_set ('__scheduler_do_now__', '0');
}
;

scheduler_init ()
;

--!AWK PUBLIC
create procedure SYS_GENERATE_ALL_OPS (in col_name varchar, in col_dtp integer := 193)
{
  declare func, args varchar;
  func :=
    case dv_type_title (col_dtp)
      when 'VARCHAR'   then 'left'
      when 'VARBINARY' then 'left'
      when 'NVARCHAR'  then 'left'
                       else ''
    end;
  args :=
    case func
      when 'left' then ', 2000'
                  else ''
    end;
  return sprintf(
    ' count (distinct "%I"), ' ||
    ' %s (min ("%I")%s), ' ||
    ' %s (max ("%I")%s), ' ||
    ' avg (raw_length("%I")), ' ||
    'count ("%I")',
    col_name,
    func, col_name, args,
    func, col_name, args,
    col_name,
    col_name);
}
;


--!AWK PUBLIC
create procedure SYS_GENERATE_ALL_VARS (in col_name varchar, in rate varchar:=null, in n_dist_rate varchar:=null )
{
  if (rate is null)
    {
  	return sprintf (' n_dist_%I, min_%I, max_%I, avg_len_%I, vals_%I', col_name, col_name, col_name, col_name, col_name);
    }
  else
    {
	if (n_dist_rate is null)
	{
  	  return sprintf (' n_dist_%I, min_%I, max_%I, avg_len_%I, vals_%I*%s', col_name, col_name, col_name, col_name, col_name, rate);
	}
	else
	{
  	  return sprintf (' n_dist_%I*%s, min_%I, max_%I, avg_len_%I, vals_%I*%s', col_name, n_dist_rate, col_name, col_name, col_name, col_name, rate);
	}
    }
}
;

create table SYS_STAT_VDB_MAPPERS (
   SVDM_TYPE varchar,
   SVDM_PROC varchar not null,
   SVDM_DBMS_NAME_MASK varchar not null,
   SVDM_DBMS_VER_MASK varchar not null,
   primary key (SVDM_TYPE, SVDM_DBMS_NAME_MASK, SVDM_DBMS_VER_MASK))
;

--!AWK AFTER
insert soft SYS_STAT_VDB_MAPPERS
  (SVDM_TYPE,
   SVDM_PROC,
   SVDM_DBMS_NAME_MASK,
   SVDM_DBMS_VER_MASK)
 values
  ('SYS_COL_STAT',
   'DB.DBA.__ORACLE_SYS_COL_STAT',
   '%ORACLE%',
   '%')
;

--!AWK AFTER
insert soft SYS_STAT_VDB_MAPPERS
  (SVDM_TYPE,
   SVDM_PROC,
   SVDM_DBMS_NAME_MASK,
   SVDM_DBMS_VER_MASK)
 values
  ('SYS_COL_STAT',
   'DB.DBA.__VIRTUOSO_SYS_COL_STAT',
   '%VIRTUOSO%',
   '%')
;

create procedure DB.DBA.__ORACLE_SYS_COL_STAT (in DSN varchar, in RT_NAME varchar, in RT_REMOTE_NAME varchar)
returns ANY
{
--  dbg_obj_print ('DB.DBA.__ORACLE_SYS_COL_STAT', DSN, RT_NAME, RT_REMOTE_NAME);
  declare _meta, _res any;

  rexecute (DSN,
    'select c.COLUMN_NAME, c.NUM_DISTINCT, NULL, NULL, c.AVG_COL_LEN, t.NUM_ROWS - c.NUM_NULLS, t.NUM_ROWS ' ||
    ' from ALL_TABLES t, ALL_TAB_COLUMNS c where t.TABLE_NAME = c.TABLE_NAME and t.OWNER = c.OWNER and ' ||
    '  t.OWNER = ? and t.TABLE_NAME = ?',
    NULL, NULL, vector (name_part (RT_REMOTE_NAME, 1, NULL), name_part (RT_REMOTE_NAME, 2, NULL)),
    NULL, _meta, _res);

  if (isarray (_res) and length (_res) > 0 and isarray (_res[0]) and isarray (_meta) and isarray (_meta[0]))
    {
      declare _inx, _len integer;
      _inx := 0;
      _len := length (_res);
      exec_result_names (_meta[0]);
      while (_inx < _len)
	{
	  exec_result (_res[_inx]);
	  _inx := _inx + 1;
	}
    }
  return NULL;
}
;

create procedure DB.DBA.__VIRTUOSO_SYS_COL_STAT (in DSN varchar, in RT_NAME varchar, in RT_REMOTE_NAME varchar)
returns ANY
{
--  dbg_obj_print ('DB.DBA.__VIRTUOSO_SYS_COL_STAT', DSN, RT_NAME, RT_REMOTE_NAME);
  declare _meta, _res any;

  rexecute (DSN,
    'select CS_COL, CS_N_DISTINCT, encode_base64 (serialize (CS_MIN)), encode_base64 (serialize (CS_MAX)), ' ||
    ' CS_AVG_LEN, CS_N_VALUES, CS_N_ROWS from ALL_COL_STAT where CS_TABLE = complete_table_name (?, 1)',
    NULL, NULL, vector (RT_REMOTE_NAME),
    NULL, _meta, _res);

  if (isarray (_res) and length (_res) > 0 and isarray (_res[0]) and isarray (_meta) and isarray (_meta[0]))
    {
      declare _inx, _len integer;
      _inx := 0;
      _len := length (_res);
      exec_result_names (_meta[0]);
      while (_inx < _len)
	{
	  declare _res_row any;
	  _res_row := _res[_inx];
	  _res_row[2] := deserialize (decode_base64 (_res_row[2]));
	  _res_row[3] := deserialize (decode_base64 (_res_row[3]));
	  exec_result (_res_row);
	  _inx := _inx + 1;
	}
    }
  return NULL;
}
;

--!AWK AFTER
insert soft SYS_STAT_VDB_MAPPERS
  (SVDM_TYPE,
   SVDM_PROC,
   SVDM_DBMS_NAME_MASK,
   SVDM_DBMS_VER_MASK)
 values
  ('SYS_COL_STAT',
   'DB.DBA.__INFORMIX_SYS_COL_STAT',
   '%INFORMIX%',
   '%')
;


create procedure DB.DBA.__INFORMIX_SYS_COL_STAT (in DSN varchar, in RT_NAME varchar, in RT_REMOTE_NAME varchar)
{
  declare _meta, _res any;
  declare i_meta, i_res any;
  declare CS_COL, CS_N_DISTINCT, CS_MIN, CS_MAX, CS_AVG_LEN, CS_N_VALUES, CS_N_ROWS int;
  declare tabid, colid int;

  rexecute (DSN, 'select t.nrows, c.colname, c.colno, c.colmin, c.colmax, c.collength, c.coltype from systables t, syscolumns c where c.tabid = t.tabid and t.owner = ? and t.tabname = ?',
      NULL, NULL, vector (name_part (RT_REMOTE_NAME, 1, NULL), name_part (RT_REMOTE_NAME, 2, NULL)), NULL, _meta, _res);

 rexecute (DSN, 'select part1, nunique from sysindexes i, systables t where t.tabid = i.tabid and t.owner = ? and t.tabname = ?',
      NULL, NULL, vector (name_part (RT_REMOTE_NAME, 1, NULL), name_part (RT_REMOTE_NAME, 2, NULL)), NULL, i_meta, i_res);

  if (isarray (_res) and length (_res) > 0 and isarray (_res[0]) and isarray (_meta) and isarray (_meta[0]))
    {
      declare _len, i_len, col_type int;
      declare arr, crow any;
      if (isarray (i_res) and length (i_res) > 0 and isarray (i_res[0]) and isarray (i_meta) and isarray (i_meta[0]))
        i_len := length (i_res);
      else
        i_len := 0;

      result_names (CS_COL, CS_N_DISTINCT, CS_MIN, CS_MAX, CS_AVG_LEN, CS_N_VALUES, CS_N_ROWS);
      arr := make_array (7, 'any');
      _len := length (_res);
      for (declare i int, i := 0; i < _len; i := i + 1)
	 {
	   crow := _res[i];
	   CS_N_ROWS := crow[0];
	   CS_COL := trim(crow[1]);
	   CS_AVG_LEN := crow[5];
	   CS_N_VALUES := CS_N_ROWS;
	   CS_N_DISTINCT := CS_N_ROWS / 10;
	   col_type := mod (crow[6], 256);

	   if (col_type = 5 or col_type = 8)
	     {
	       CS_AVG_LEN := crow[5]/256;
    }

	   if (col_type = 0 or col_type = 13 or col_type = 15 or col_type = 16)
	     {
	       if (crow[5] > 0)
		 {
		   CS_AVG_LEN := mod (crow[5], 256);
		 }
  else
		 {
		   CS_AVG_LEN := mod ((crow[5] + 65536), 256);
		 }
	     }
	   else if (col_type = 10 or col_type = 14)
	     {
	       CS_AVG_LEN := mod (crow[5], 256);
	     }

	   if (col_type > 0 and col_type < 7)
	     {
	       CS_MIN := crow[3];
	       CS_MAX := crow[4];
	     }
	   else
	     {
	       CS_MIN := null;
	       CS_MAX := null;
	     }

	   for (declare j int, j := 0; j < i_len; j := j + 1)
	      {
                if (i_res[j][0] = crow[2])
    {
		    CS_N_DISTINCT := i_res[j][1];
		    j := i_len;
		  }
	      }

	   if (cs_n_distinct is null) cs_n_distinct := cs_n_rows;
	   result (CS_COL, CS_N_DISTINCT, CS_MIN, CS_MAX, CS_AVG_LEN, CS_N_VALUES, CS_N_ROWS);
	 }
    }
  return null;
}
;


create procedure SYS_STAT_VDB_SYNC ()
{
  declare _ds_conn_str any;
  for select RT_DSN, RT_REMOTE_NAME, DS_CONN_STR, RT_NAME
    from DB.DBA.SYS_REMOTE_TABLE, DB.DBA.SYS_DATA_SOURCE where RT_DSN = DS_DSN do
      {
	declare rc int;
        _ds_conn_str := deserialize (DS_CONN_STR);
	rc := SYS_STAT_ANALYZE_VDB (RT_DSN, RT_REMOTE_NAME, _ds_conn_str, RT_NAME, 10, 1);
	if (rc = 1)
	  {
	    commit work;
	  }
      }
}
;


--!AWK PUBLIC
create procedure SYS_STAT_ANALYZE_VDB (
	in _ds_dsn varchar,
	in _rt_remote_name varchar,
	in _ds_conn_str any,
	in tb_name varchar,
	in perc_trsh int := 0,
	in logerr int := 0
	)
{
      declare vdb_stats_mapper varchar;
      declare exit handler for sqlstate '*', NOT FOUND { goto map_done; };
      declare _dbms_name, _dbms_ver varchar;
      _dbms_name := get_keyword (17, _ds_conn_str, '');
      _dbms_ver := get_keyword (18, _ds_conn_str, '');

      vdb_stats_mapper := NULL;
      select top 1 SVDM_PROC into vdb_stats_mapper from SYS_STAT_VDB_MAPPERS
      where
       SVDM_TYPE = 'SYS_COL_STAT' and
       upper (_dbms_name) like SVDM_DBMS_NAME_MASK and
       upper (_dbms_ver) like SVDM_DBMS_VER_MASK;

      if (vdb_stats_mapper is null)
	goto map_done;

      declare res, _stat, _meta, _err any;
  _stat := '00000';
      if (0 <> exec (sprintf ('"%I" (?, ? ,?)', vdb_stats_mapper),
	_stat, _err, vector (_ds_dsn, tb_name, _rt_remote_name), 10000, _meta, res))
	goto map_done;

      if (not isarray (res))
	goto map_done;

      if (length (res) = 0)
	goto map_done;

      if (not isarray (res[0]))
	goto map_done;

      if (length (res[0]) < 7)
	goto map_done;

  if (perc_trsh > 0)
    {
      foreach (any elm in res) do
	{
	  declare col_name varchar;
	  declare nrows, n_distinct int;
	  declare onrows, on_distinct int;
	  declare _percent, _base int;


	  col_name := elm[0];
	  n_distinct := elm[1];
	  nrows := elm[6];

	  whenever not found goto update_stats;
	  select CS_N_DISTINCT, CS_N_ROWS into on_distinct, onrows
	      from DB.DBA.SYS_COL_STAT where CS_TABLE = tb_name and CS_COL = col_name;

	  if (nrows <> onrows)
	    {
	      _base := __min (onrows, nrows);
	      if (_base > 0)
		_percent := ((abs (nrows - onrows)*100)/_base);
 	      else
		_percent := 100;
	      if (_percent >= perc_trsh)
		goto update_stats;
	    }

	  if (n_distinct <> on_distinct)
	    {
	      _base := __min (n_distinct, on_distinct);
	      if (_base > 0)
	        _percent := ((abs (n_distinct - on_distinct)*100)/_base);
	      else
	        _percent := 100;
	      if (_percent >= perc_trsh)
		goto update_stats;
	    }

	}
      return 0;
    }
update_stats:;
      declare res_len, res_inx integer;
      res_len := length (res);
      res_inx := 0;
      delete from DB.DBA.SYS_COL_STAT where CS_TABLE = tb_name;
      while (res_inx < res_len)
	{
	  declare rr, _min, _max any;
	  rr := res[res_inx];
          _min := rr[2];
          _max := rr[3];
          -- limit the min/max so they fit on the row.
      if (isstring (_min) or iswidestring (_min) or isbinary (_min))
            _min := left (_min, 1000);
      if (isstring (_max) or iswidestring (_max) or isbinary (_max))
            _max := left (_max, 1000);
	  insert into DB.DBA.SYS_COL_STAT
	    (CS_TABLE, CS_COL, CS_N_DISTINCT, CS_MIN, CS_MAX, CS_AVG_LEN, CS_N_VALUES, CS_N_ROWS)
	   values
	    (tb_name, rr[0], rr[1], _min, _max, rr[4], rr[5], rr[6]);
	   res_inx := res_inx + 1;
	 }
      __ddl_changed (tb_name);
  -- stats are done
  if (logerr)
    {
      log_message (sprintf ('The statistics for table %s has been changed', tb_name));
    }
  return 1;
map_done:;
  if (logerr and _stat <> '00000')
    log_message (sprintf ('Can\'t contact to the DSN "%s" to refresh statistics on table "%s"', _ds_dsn, tb_name));
  -- stats are not done
  return 0;
}
;


--!AWK PUBLIC
create procedure SYS_STAT_ANALYZE (in tb_name varchar, in pcnt integer:=5, in ignore_vdb integer:=1)
{
  declare stmt, proc_name varchar;
  declare proc any;
  declare cr cursor for
      select c."COLUMN", c.COL_DTP
      from DB.DBA.SYS_KEYS k, DB.DBA.SYS_KEY_PARTS kp, DB.DBA.SYS_COLS c
      where
        k.KEY_TABLE = tb_name and
	c."COLUMN" <> '_IDN' and
	k.KEY_IS_MAIN = 1 and
	k.KEY_MIGRATE_TO is null and
	kp.KP_KEY_ID = k.KEY_ID and
	COL_ID = KP_COL and
	COL_DTP not in (125, 131, 132, 134, 254);
  declare rc integer;
  declare is_vdb integer;
  declare tot_count integer;
  declare _ds_dsn, _rt_remote_name varchar;
  declare _ds_conn_str any;

  _ds_dsn := _rt_remote_name := NULL;
    {
      declare exit handler for not found { _ds_dsn := _rt_remote_name := NULL; };

      select RT_DSN, RT_REMOTE_NAME, deserialize (DS_CONN_STR)
	     into _ds_dsn, _rt_remote_name, _ds_conn_str
	     from DB.DBA.SYS_REMOTE_TABLE, DB.DBA.SYS_DATA_SOURCE
	     where RT_NAME = tb_name and RT_DSN = DS_DSN;
   }

  if (_ds_dsn is null)
    is_vdb := 0;
  else
    is_vdb := 1;

  if (is_vdb and ignore_vdb)
    return;

  rc := 0;

  if (pcnt > 0)
    rc := SYS_STAT_ANALYZE_VDB (_ds_dsn, _rt_remote_name, _ds_conn_str, tb_name);

  -- stats are done via vdb statistics
  if (rc = 1)
    return;

  connection_set ('rnd-stat-rate', 0.0);

  proc := string_output ();
	  proc_name := sprintf ('"%I".."STAT_ANALYZE_%I_%I"',
	name_part (tb_name, 0),
	name_part (tb_name, 1),
	name_part (tb_name, 2));
  http (sprintf ('create procedure %s () { \n', proc_name), proc);
  http ('set isolation=''uncommitted''; \n', proc);
  http (sprintf ('delete from DB.DBA.SYS_COL_STAT where CS_TABLE = ''%S''; \n', tb_name), proc);
  open cr;
  whenever not found goto done;
  declare all_ops varchar;
  declare all_vars varchar;

  all_ops := '';
  all_vars := '';

  while (1)
    {
      declare col_name, stat, msg varchar;
      declare col_dtp integer;
      fetch cr into col_name, col_dtp;
      http (sprintf (' declare n_dist_%I integer; \n', col_name), proc);
      http (sprintf (' declare min_%I any; \n', col_name), proc);
      http (sprintf (' declare max_%I any; \n', col_name), proc);
      http (sprintf (' declare avg_len_%I integer; \n', col_name), proc);
      http (sprintf (' declare vals_%I integer; \n', col_name), proc);

      if (all_ops = '')
	{
	  all_ops := SYS_GENERATE_ALL_OPS (col_name, col_dtp);
	  all_vars := SYS_GENERATE_ALL_VARS (col_name);
	}
      else
	{
	  all_ops := concat (all_ops, ',', SYS_GENERATE_ALL_OPS (col_name, col_dtp));
	  all_vars := concat (all_vars, ',', SYS_GENERATE_ALL_VARS (col_name));
	}
     }
done:
  close cr;
  if (all_ops = '')
   goto fin;

  http ('declare n_rows varchar; \n', proc);

  if (pcnt)
    {
	if (is_vdb = 1)
	  {
	    http ('declare tot_count integer;\n', proc);
	    http (sprintf ('tot_count := DB.DBA.__VD_GET_SQLSTATS_COUNT (''%S'', ''%S'');\n',
	      _ds_dsn, _rt_remote_name), proc);
	    http ('if (tot_count is NULL)\n', proc);
	    http ('{\n', proc);
	    http (sprintf ('  declare cr_count cursor for select count (*) from "%I"."%I"."%I";\n',
	        name_part (tb_name, 0),
		name_part (tb_name, 1),
		name_part (tb_name, 2)), proc);
	    http ('  open cr_count;\n fetch cr_count into tot_count;\n close cr_count;\n', proc);
	    http ('}\n', proc);
	    http ('declare cr2 cursor for \n', proc);
	    http (sprintf ('select %s, count (*) from (select top 1000 * from \"%I\".\"%I\".\"%I\") f; \n',
		        all_ops,
			name_part (tb_name, 0),
			name_part (tb_name, 1),
			name_part (tb_name, 2)), proc);
	  }
	else
	  {
	    http ('declare cr2 cursor for \n', proc);
	    http (sprintf ('select %s, count (*) from "%I"."%I"."%I" table option ( random %d ); \n',
	        all_ops,
		name_part (tb_name, 0),
		name_part (tb_name, 1),
		name_part (tb_name, 2),
		pcnt), proc);
	  }
    }
  else
    {
	http ('declare cr2 cursor for \n', proc);
	http (sprintf ('select %s, count (*) from "%I"."%I"."%I"; \n',
	        all_ops,
		name_part (tb_name, 0),
		name_part (tb_name, 1),
		name_part (tb_name, 2)), proc);
   }


  http ('open cr2; \n', proc);
  http (sprintf ('fetch cr2 into %s, n_rows; \n', all_vars) , proc);


  open cr;
  whenever not found goto done2;

  if (pcnt)
    {
	http (' declare rate float; \n', proc);
	http (' declare ndist_rate float; \n', proc);
	if (is_vdb = 1)
	  {
	    http (' if (tot_count > 1000) rate := tot_count / 1000.0; \n', proc);
	    http (' else rate := 1; \n', proc);
	  }
	else
	  {
	    http (' rate := connection_get (\'rnd-stat-rate\'); \n', proc);
	  }
    }
  while (1)
    {
      declare col_name varchar;
      declare col_dtp integer;
      fetch cr into col_name, col_dtp;

      if (pcnt)
	{
	  http (sprintf (' if (rate = 0 AND vals_%I <> 0 ) { rate := 1; }; \n', col_name), proc);
	  http (sprintf (' if (n_dist_%I < 20) { ndist_rate := 1; } else {ndist_rate := rate; }; \n', col_name), proc);

      	  http ('insert into DB.DBA.SYS_COL_STAT (CS_TABLE,CS_COL,CS_N_DISTINCT,CS_MIN,CS_MAX, CS_AVG_LEN, CS_N_VALUES,CS_N_ROWS) ', proc);
      	  http (sprintf ('values (\'%S\',\'%S\',%s, n_rows * %s); \n',
		tb_name, col_name, SYS_GENERATE_ALL_VARS (col_name, 'rate', 'ndist_rate'), 'rate'), proc);
	}
      else
	{
      	  http ('insert into DB.DBA.SYS_COL_STAT (CS_TABLE,CS_COL,CS_N_DISTINCT,CS_MIN,CS_MAX, CS_AVG_LEN, CS_N_VALUES,CS_N_ROWS) ', proc);
      	  http (sprintf ('values (\'%S\',\'%S\',%s, n_rows); \n',
		tb_name, col_name, SYS_GENERATE_ALL_VARS (col_name)), proc);
	}

    }
done2:
  http ('close cr2; \n', proc);
  close cr;
fin:


  http (sprintf ('__ddl_changed (''%S''); \n', tb_name), proc);
  http ('}\n', proc);

  proc := string_output_string (proc);
--  dbg_obj_print (proc);
  exec (proc, NULL, NULL);
  exec (sprintf ('%s ()', proc_name), NULL, NULL);
  exec (sprintf ('drop procedure %s', proc_name), NULL, NULL);
}
;


--!AWK PUBLIC
create procedure SYS_DB_STAT (in pcnt integer:=null, in ignore_vdb integer:=1)
{
        declare cnt integer;
        cnt:=0;
	if (pcnt is null) pcnt := 5;
        for select distinct (KEY_TABLE) as TB_NAME from SYS_KEYS where
                not exists (
                        select * from SYS_VIEWS where KEY_TABLE = V_NAME
                ) do {
                        if (TB_NAME <> 'DB.DBA.SYS_COL_STAT')
                        {
                                SYS_STAT_ANALYZE (TB_NAME, pcnt, ignore_vdb);
                                cnt := cnt + 1;
                        }
                }
        return cnt;
}
;

--!AWK PUBLIC
create procedure SYS_STAT_HISTOGRAM (in tb_name varchar, in col_name varchar,
    in n_buckets integer, in prec integer := 1)
{
  declare proc any;
  declare proc_name,escaped_tb_name varchar;
  declare is_inx, is_analyzed integer;

  select count (*) into is_analyzed from DB.DBA.SYS_COL_STAT where CS_TABLE = tb_name and CS_COL = col_name;

  select count (*) into is_inx from DB.DBA.SYS_KEYS, DB.DBA.SYS_KEY_PARTS, DB.DBA.SYS_COLS
      where
        KP_KEY_ID = KEY_ID and
	KP_NTH = 0 and
	KP_COL = COL_ID and
	KEY_TABLE = tb_name and
	"COLUMN" = col_name;

  proc_name := sprintf ('"%I".."STAT_HIST_%I_%I_%I"',
		 name_part (tb_name, 0),
		 name_part (tb_name, 1),
		 name_part (tb_name, 2),
		 col_name);
  escaped_tb_name := sprintf ('"%I"."%I"."%I"',
		 name_part (tb_name, 0),
		 name_part (tb_name, 1),
		 name_part (tb_name, 2));
  proc := string_output();
  http (sprintf ('create procedure %s (in n_buckets integer := %d, in prec integer := %d) {\n',
	proc_name, n_buckets, prec), proc);
  http ('declare row_cnt, inx, last_inx integer; \n', proc);
  http ('declare _column_val any; \n', proc);
  http ('set isolation=''uncommitted''; \n', proc);
  http ('inx := 0; \n', proc);
  http (sprintf (
	'delete from DB.DBA.SYS_COL_HIST where CH_TABLE = ''%S'' and CH_COL = ''%S''; \n',
	tb_name, col_name), proc);
  if (is_inx = 0)
    {
      http ('row_cnt := 0; \n', proc);
      http (sprintf (
	    'for select "%I" from %s where \n',
	   col_name, escaped_tb_name), proc);
      http (sprintf (
            ' (row_cnt := row_cnt + 1, mod (row_cnt - 1, prec, "%I")) = 0 order by "%I" do\n{\n',
	    col_name, col_name), proc);
      http (sprintf (
	    '  _column_val := "%I"; ', col_name), proc);
      http ('if (mod (inx, (row_cnt / n_buckets) / prec) = 0) \n{\n', proc);
    }
  else
    {
      http (sprintf ('select count (*) into row_cnt from %s; \n',
	    escaped_tb_name), proc);
      http (sprintf (
	    'for select "%I" from %s order by "%I" do \n{\n',
	   col_name, escaped_tb_name, col_name), proc);
      http ('if (mod (inx, prec) = 0 and mod (inx, row_cnt / (n_buckets * prec)) = 0)\n{\n', proc);
    }
  http ('insert into DB.DBA.SYS_COL_HIST (CH_TABLE, CH_COL, CH_NTH_SAMPLE, CH_VALUE) values\n', proc);
  http (sprintf (
	' (''%S'', ''%S'', inx, "%I"); \n',
	tb_name, col_name, col_name), proc);
  http ('last_inx := inx;\n}\n inx := inx + 1;\n}\n', proc);
  http ('if (row_cnt > 0 and last_inx < inx)\n', proc);
  http ('insert into DB.DBA.SYS_COL_HIST (CH_TABLE, CH_COL, CH_NTH_SAMPLE, CH_VALUE) values\n', proc);
  http (sprintf (
	' (''%S'', ''%S'', inx, _column_val); \n',
	tb_name, col_name), proc);
  if (is_analyzed > 0)
    http (sprintf (
	  '__ddl_changed (''%S'');\n',
	  tb_name), proc);
  http ('}', proc);
  proc := string_output_string (proc);
  exec (proc);
  exec (sprintf ('%s ()', proc_name));
  exec (sprintf ('drop procedure %s', proc_name));

  if (is_analyzed = 0)
    DB..SYS_STAT_ANALYZE (tb_name, prec);
}
;

create table
DB.DBA.SYS_SOAP_DATATYPES (SDT_NAME varchar,
                           SDT_SCH long varchar,
			   SDT_SOAP_SCH long varchar,
			   SDT_TYPE integer,
			   SDT_UDT varchar,
			   primary key (SDT_NAME, SDT_TYPE))
;


--!AFTER
create procedure
DB.DBA.SOAP_DATATYPES_UPGRADE ()
{
  if (exists (select 1 from SYS_COLS where \TABLE = 'DB.DBA.SYS_SOAP_DATATYPES' and \COLUMN = 'SDT_TYPE') and
      exists (select 1 from SYS_COLS where \TABLE = 'DB.DBA.SYS_SOAP_DATATYPES' and \COLUMN = 'SDT_UDT') )
    return;
  log_message ('Upgrading the SYS_SOAP_DATATYPES table');
  execstr ('alter table DB.DBA.SYS_SOAP_DATATYPES rename DB.DBA.SYS_SOAP_DATATYPES_OLD');
  execstr ('create table DB.DBA.SYS_SOAP_DATATYPES (SDT_NAME varchar, SDT_SCH long varchar, SDT_SOAP_SCH long varchar, SDT_TYPE integer, SDT_UDT varchar, primary key (SDT_NAME, SDT_TYPE))');
  execstr ('insert into DB.DBA.SYS_SOAP_DATATYPES (SDT_NAME, SDT_SCH, SDT_SOAP_SCH, SDT_TYPE) select (case when strrchr (SDT_NAME, '':'') is null then concat (''services.wsdl:'',SDT_NAME) else SDT_NAME end) , SDT_SCH, SDT_SOAP_SCH, 0 from DB.DBA.SYS_SOAP_DATATYPES_OLD');
}
;

--!AFTER
DB.DBA.SOAP_DATATYPES_UPGRADE ()
;

--!AFTER_AND_BEFORE DB.DBA.SYS_SOAP_DATATYPES SDT_TYPE !
create procedure
soap_dt_define (in name varchar, in sch varchar, in udt_name varchar := null)
{
  declare xt, xte any;
  declare is_elem integer;
  xt := NULL; xte := null; is_elem := 0;
  if (sch is not null)
    {
      declare err, name1, tns varchar;
      if (isentity (sch))
	xte := sch;
      else
	xte := xml_tree_doc (xml_tree (sch));
      xt := xslt ('http://local.virt/soap_sch', xte, vector ('udt_struct', case when isstring(udt_name) then 1 else 0 end));
      err := xpath_eval ('string(//@error)', xt, 1);
      if (xpath_eval ('/element', xte, 1) is not null)
	is_elem := 1;
      if (xpath_eval ('/attribute', xte, 1) is not null)
	is_elem := -1;
      err := cast (err as varchar);
      if (err <> '')
        signal ('22023', err, 'SODT1');
      name1 := cast(xpath_eval ('string(/@name)', xt, 1) as varchar);
      tns := cast(xpath_eval ('string(/@targetNamespace)', xte, 1) as varchar);
      if (tns is null or tns = '')
        name := name1;
      else
	name := sprintf ('%s:%s', tns, name1);
      insert replacing DB.DBA.SYS_SOAP_DATATYPES (SDT_NAME,SDT_SCH,SDT_TYPE, SDT_UDT)
	  values (name, sch, is_elem, udt_name);
      {
	declare cmpl, cname, cname2,  sch2 varchar;
        cmpl := xpath_eval ('/element/complexType', xte, 1);
        -- must test for child elements
        if (cmpl is not null)
          {
            cname := sprintf ('elementType__%s', name1);
            if (tns is null or tns = '')
              cname2 := cname;
            else
              cname2 := sprintf ('%s:%s', tns, cname);
            sch2 := xslt ('http://local.virt/soap_sch', cmpl, vector ('type_name', cname));
            __soap_dt_define (cname2, sch2, sch2, 0, udt_name);
            insert replacing DB.DBA.SYS_SOAP_DATATYPES (SDT_NAME,SDT_SCH, SDT_TYPE, SDT_UDT) values (cname2, sch2, 0, udt_name);
	  }
      }
    }
  else
    delete from DB.DBA.SYS_SOAP_DATATYPES where SDT_NAME = name;
  __soap_dt_define (name, xt, xte, is_elem, udt_name);
  return name;
}
;



--!AWK PUBLIC
create procedure SET_IDENTITY_COLUMN (in tbl_name varchar, in col_name varchar, in num integer)
{
  if (not exists (select 1 from DB.DBA.SYS_COLS where "TABLE" = tbl_name and "COLUMN" = col_name))
    {
      if (not exists (select 1 from DB.DBA.SYS_COLS where "TABLE" = tbl_name))
        signal ('10050', concat ('No table ', tbl_name, ' in call to SET_IDENTITY_COLUMN'));
      else
        signal ('10050', concat ('No column ', col_name, ' in table ', tbl_name, ' in call to SET_IDENTITY_COLUMN'));
    }
  return sequence_set (concat (name_part (tbl_name, 0, 'DB'), '.',
	name_part (tbl_name, 1, user), '.', tbl_name, '.', col_name), num, 0);
}
;

--!AWK PUBLIC
create procedure GET_IDENTITY_COLUMN (in tbl_name varchar, in col_name varchar, in no_check int := 0)
{
  if (no_check = 0 and not exists (select 1 from DB.DBA.SYS_COLS where "TABLE" = tbl_name and "COLUMN" = col_name))
    {
      if (not exists (select 1 from DB.DBA.SYS_COLS where "TABLE" = tbl_name))
        signal ('10050', concat ('No table ', tbl_name, ' in call to GET_IDENTITY_COLUMN'));
      else
        signal ('10050', concat ('No column ', col_name, ' in table ', tbl_name, ' in call to GET_IDENTITY_COLUMN'));
    }
  return sequence_set (concat (name_part (tbl_name, 0, 'DB'), '.',
	name_part (tbl_name, 1, user), '.', tbl_name, '.', col_name), 0, 2);
}
;

xml_add_system_path('file://system/')
;


create procedure
DAV_USER_SET_PASSWORD (in name varchar, in passwd varchar)
{
  USER_PASSWORD_SET (name, passwd);
  --declare _u_id, _u_group integer;
  --select U_ID, U_GROUP into _u_id, _u_group from SYS_USERS where U_NAME = USER;
  --if (not (_u_id = 0 or _u_group = 0))
  --  signal ('42000', 'Function dav_user_set_password restricted to dba group', 'DA009');
  --if (not exists (select 1 from WS.WS.SYS_DAV_USER where U_NAME = name))
  --  signal ('42000', concat ('The user ''', name, ''' does not exist'), 'DA010');
  --if (not isstring (passwd) or length (passwd) < 1)
  --  signal ('42000', concat ('The new password for ''', name, ''' cannot be empty'), 'DA011');
  --update WS.WS.SYS_DAV_USER set U_PWD = pwd_magic_calc (name, passwd) where U_NAME = name;
  --return 0;
}
;

--!AWK PLBIF http_client
create procedure DB.DBA.HTTP_CLIENT (
    in url varchar,
    in uid varchar := null,
    in pwd varchar := null,
    in http_method varchar := 'GET',
    in http_headers varchar := null,
    in body varchar := null,
    in cert_file varchar := null,
    in cert_pwd varchar := null
  )
{

  if (cert_file is null and url like 'https://%')
    cert_file := '1';
  return http_client_internal (url, uid, pwd, http_method, http_headers, body, cert_file, cert_pwd);
}
;

--!AWK PLBIF http_client_ext
create procedure DB.DBA.HTTP_CLIENT_EXT (
    in url varchar,
    in uid varchar := null,
    in pwd varchar := null,
    in http_method varchar := 'GET',
    in http_headers varchar := null,
    in body varchar := null,
    in cert_file varchar := null,
    in cert_pwd varchar := null,
    inout headers any
  )
{

  if (cert_file is null and url like 'https://%')
    cert_file := '1';
  return http_client_internal (url, uid, pwd, http_method, http_headers, body, cert_file, cert_pwd, headers);
}
;

create procedure vsmx_user_check (in name varchar, in pass varchar)
{
  return 1;
}
;

--!AWK PUBLIC
create procedure
DB.DBA.SOAP_VSMX (in path any, in params any, in lines any)
{ ?>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN"
 "http://www.w3.org/TR/1999/REC-html401-19991224/loose.dtd">
<HTML>
 <HEAD>
<STYLE>
BODY
{
    MARGIN-TOP: 0px;
    FONT-SIZE: 80%;
    MARGIN-LEFT: 0em;
    COLOR: #000000;
    MARGIN-RIGHT: 0em;
    FONT-FAMILY: Verdana, 'MS Serif', Serif;
    BACKGROUND-COLOR: #ffffff
}
.head1
{
    PADDING-BOTTOM: 5px;
    MARGIN-LEFT: -3em;
    COLOR: #191970;
    LINE-HEIGHT: normal;
    MARGIN-RIGHT: -3em;
    PADDING-TOP: 5px;
    BORDER-BOTTOM: navy thin solid;
    FONT-FAMILY: Verdana, Arial, Helvetica, Lucida, Sans-Serif;
    BACKGROUND-COLOR: skyblue;
    TEXT-ALIGN: right
}
DIV.foot
{
    CLEAR: left;
    BORDER-TOP: lightslategray thin solid;
    FONT-SIZE: 10px;
    LINE-HEIGHT: normal;
    FONT-FAMILY: Verdana, Arial, Helvetica, Lucida, Sans-Serif;
    TEXT-ALIGN: right
}
H1
{
    PADDING-RIGHT: 3em;
    MARGIN-TOP: 5px;
    FONT-SIZE: 185%;
    MARGIN-BOTTOM: 5px;
    MARGIN-LEFT: 0em
}
A
{
    COLOR: blue;
    TEXT-DECORATION: none
}
A:hover
{
    TEXT-DECORATION: underline
}
.operation
{
    PADDING-RIGHT: 10px;
    PADDING-LEFT: 30px;
    PADDING-BOTTOM: 10px;
    PADDING-TOP: 10px;
    VERTICAL-ALIGN: top;
}
.soaplist
{
    VERTICAL-ALIGN: top;
    PADDING-RIGHT: 5px;
    PADDING-LEFT: 25px;
    PADDING-BOTTOM: 10px;
    MARGIN: 0px;
    WIDTH: 225px;
    PADDING-TOP: 10px;
    BACKGROUND-COLOR: gainsboro
}
.soapdesc
{
    FONT-SIZE: 90%;
    FONT-FAMILY: Tahoma
}
INPUT
{
    BORDER-RIGHT: silver 1px solid;
    BORDER-TOP: silver 1px solid;
    BORDER-LEFT: silver 1px solid;
    BORDER-BOTTOM: silver 1px solid;
    FONT-FAMILY: Tahoma
}
.btns
{
    TEXT-ALIGN: right
}
TABLE.service
{
    BORDER-RIGHT: #ebebeb 1px solid;
    BORDER-TOP: #ebebeb 1px solid;
    BORDER-LEFT: #ebebeb 1px solid;
    BORDER-BOTTOM: #ebebeb 1px solid;
    FONT-FAMILY: Tahoma
}
TH.service
{
    BACKGROUND-COLOR: silver;
    TEXT-ALIGN: left
}
H2
{
    FONT-SIZE: 150%;
    MARGIN-LEFT: -20px
}
H3
{
    FONT-SIZE: 120%;
    MARGIN-BOTTOM: 0px;
    MARGIN-LEFT: -10px
}
.soapli
{
    PADDING-BOTTOM: 5px;
    TEXT-INDENT: -20px
}
TD.service
{
    BACKGROUND-COLOR: #f0f0f0
}
.response
{
    BORDER-RIGHT: #f0f0f0 1px solid;
    PADDING-RIGHT: 2px;
    BORDER-TOP: #f0f0f0 1px solid;
    PADDING-LEFT: 2px;
    PADDING-BOTTOM: 2px;
    BORDER-LEFT: #f0f0f0 1px solid;
    PADDING-TOP: 2px;
    BORDER-BOTTOM: #f0f0f0 1px solid
}
.details
{
    PADDING-RIGHT: 2px;
    PADDING-LEFT: 30px;
    PADDING-BOTTOM: 2px;
    PADDING-TOP: 10px;
    BACKGROUND-COLOR: #f0f0f0;
    TEXT-ALIGN: left
}
.level1
{
    COLOR: blue
}
.level2
{
    COLOR: red
}
.level3
{
    COLOR: green
}
.level4
{
    COLOR: teal
}
.attribname
{
    TEXT-ALIGN: right;
}
.attrib
{
    COLOR: #990000
}
</STYLE>
<TITLE>Web Service Testing</TITLE>
 </HEAD>
 <BODY>
<DIV class="head1"><H1>Web Services Test Page (VSMX)</H1></DIV>
<?vsp
 declare this_page varchar;
 declare wsdl any;
 declare inx, len, _u_id integer;
 this_page := 'services.vsmx';
 set http_charset='UTF-8';
 http_header ('Cache-Control: no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: Thu, 01 Dec 1994 01:02:03 GMT\r\n');

?>
<DIV class="soappage">
<TABLE BORDER="0" CELLPADDING="0" CELLSPACING="0">
<TR><TD class="soaplist">
<H2>Services Available</H2>
<?vsp
     declare xt any;
     wsdl := soap_wsdl();
     if (not (registry_get ('old_vsmx') = '1') and isstring (file_stat (http_root()||'/vsmx/oper.vspx')))
       {
         declare sid any;
         sid := vspx_sid_generate ();
         insert into VSPX_SESSION (VS_REALM, VS_SID, VS_UID, VS_STATE, VS_EXPIRY)
		values ('vsmx', sid, null,
		serialize (vector ('wsdl', wsdl, 'loc', WS.WS.EXPAND_URL (HTTP_REQUESTED_URL(),'services.wsdl'))),
		now ());
         http_request_status ('HTTP/1.1 302 Found');
         http_header (sprintf ('Location: /vsmx/oper.vspx?sid=%s&realm=vsmx\r\n', sid));
         http_rewrite ();
         return;
       }
     xt := xml_tree_doc (wsdl);
     inx := 0;
     _u_id := (select top 1 U_ID from DB.DBA.SYS_USERS where U_NAME = http_map_get ('soap_uid'));
     for select 0 as TP, P_NAME as operation, coalesce (P_TEXT, blob_to_string (P_MORE)) as content
       from DB.DBA.SYS_PROCEDURES where (name_part (P_NAME, 0) = http_map_get ('soap_qual')
	   and name_part (P_NAME,1) = http_map_get ('soap_uid'))
	   or exists (select 1 from DB.DBA.SYS_GRANTS where G_USER = _u_id and G_OP = 32 and G_OBJECT = P_NAME)

	   union select 0 as TP, G_OBJECT as operation, '' as content from DB.DBA.SYS_GRANTS where
	   G_USER = _u_id and G_OP = 32 and __proc_exists (G_OBJECT) is not null
	   and not exists (select 1 from DB.DBA.SYS_PROCEDURES where G_OBJECT = P_NAME)

           union select 1 as TP, M_NAME as operation, blob_to_string (M_TEXT) as content
		from DB.DBA.SYS_METHODS, DB.DBA.SYS_USER_TYPES where M_ID = UT_ID and
	   exists (select 1 from DB.DBA.SYS_GRANTS where G_USER = _u_id and G_OP = 32 and G_OBJECT = UT_NAME)
	   do
       {
	 declare comments, title, elm, operation1, q, o varchar;

	 q := name_part (operation, 0);
	 o := name_part (operation, 1);

         if (TP = 1)
           operation1 := operation;
	 else if ((length (q) + length (o) + 3) < length (operation))
	   operation1 := substring (operation, length (q) + length (o) + 3, length (operation));
	 else
	   goto nxt;

	 operation := operation1;

         elm := xpath_eval (sprintf ('/definitions/portType/operation[@name = \'%s\']', operation), xt);
	 if (elm is null)
	   goto nxt;
         title := regexp_match ('--##.*', content);
         if (title is null)
           title := '';
	 else
	   title := substring (title, 5, length (title));
?>
    <DIV class="soapli"><A href="<?=this_page?>?operation=<?=operation?>"><?=operation?></A><BR />
    <SPAN class="soapdesc"><?=title?></SPAN></DIV>
<?vsp
        inx := inx + 1;
nxt:;
       }
?>
</TD>
<TD class="operation">
<?vsp

   if ({?'operation'} is not null )
   {
     declare xe, pars any;
     declare xps, url varchar;
     wsdl := soap_wsdl();
     xe := xml_tree_doc (wsdl);
     if (xpath_eval (sprintf ('/definitions/binding/operation[@name="%s"]/operation[@style="document"]', {?'operation'}), xe) is null)
       {
         xps := sprintf ('/definitions/message[@name = \'%sRequest\']/part', {?'operation'});
       }
     else if (xpath_eval (sprintf ('/definitions/message[@name = \'%sRequest\']/part[@name="parameters"]', {?'operation'}), xe) is not null)
       {
         declare elm_name any;
         declare pos int;

         xps := sprintf ('/definitions/message[@name = \'%sRequest\']/part/@element', {?'operation'});
         elm_name := cast (xpath_eval (xps, xe) as varchar);
         pos := strrchr (elm_name, ':');
         if (pos is not null)
           {
             elm_name := subseq (elm_name, pos + 1, length (elm_name));
           }
         xps := sprintf ('/definitions/types/schema/element[@name = "%s"]//element', elm_name);
       }
     else
       {
         xps := sprintf ('/definitions/message[@name = \'%sRequest\']/part', {?'operation'});
       }

     pars := xpath_eval (xps, xe, 0);
     url := cast (xpath_eval ('/definitions/service/port/address/@location', xe, 1) as varchar);
     len := length (pars);
     inx := 0;
?>
<H2><?={?'operation'}?></H2>
<H3>Details</H3>
<P>The service end point is: <?=url?></P>
<P>The WSDL end point is: <A href="<?=url?>/services.wsdl"><?=url?>/services.wsdl</A></P>
<H3>Test</H3>
    <FORM method="POST" action="<?=this_page?>">
    <INPUT type="hidden" name="operation" value="<?={?'operation'}?>" >
    <INPUT type="hidden" name="url" value="<?=url?>" >
<TABLE class="service" border="0" cellpadding="2" cellspacing="2">
<TR>
  <TH class="service">Parameter</TH>
  <TH class="service">Value</TH>
  <TH class="service">Type</TH>
</TR>
<?vsp
     while (inx < len)
       {
	 declare n, t varchar;
         n := xpath_eval ('@name', pars[inx], 1);
         t := xpath_eval ('@type', pars[inx], 1);
         n := cast (n as varchar); t := cast (t as varchar);
         if (t like 'http://www.w3.org/____/XMLSchema:%')
	   {
	     t := substring (t, length ('http://www.w3.org/____/XMLSchema:') + 1, length (t));
	     t := concat ('xsd:', t);
	   }
	 else if (strchr (t, ':') is not null and t not like 'xsd:%')
	   {
	     declare colon integer;
             colon := strrchr (t, ':');
             t := substring (t, colon + 1, length (t));
	     t := concat ('s', t);
	   }
?>
    <TR>
      <TD class="service"><?=n?></TD>
      <?vsp if (t like 'xsd:%') { ?>
      <TD class="service"><input type="text" name="<?=n?>" size="40" /></TD>
      <?vsp } else { ?>
      <TD class="service"><textarea name="<?=n?>" rows=10 cols="40"><?vsp
	 if (t like '_:%' and t not like '_:ArrayOf%')
	   {
	     declare struct, t1 any;
	     declare i, l integer;
             t1 := substring (t, 3, length (t));
             xps :=
        sprintf ('/definitions/types/schema/complexType[@name = ''%s'']/*/element/@name', t1);
             struct := xpath_eval (xps, xe, 0);
             i := 0; l := length (struct);
	     while (i < l)
	       {
		 http (cast (struct[i] as varchar));
		 http ('=\r\n');
                 i := i + 1;
	       }
	   }
      ?></textarea></TD>
      <?vsp } ?>
      <TD class="service"><SPAN class="datatype"><?=t?></SPAN>
        <input type="hidden" name="<?=n?>_type" value="<?=t?>"></TD>
    </TR>
<?vsp
         inx := inx + 1;
       }
     if (not inx)
       {
?>
    <TR><TD class="service" colspan="2">No input parameters are required for this service.</TD></TR>
<?vsp
       }
?>
    <TR><TD class="btns" colspan="2"><input type="submit" name="callit" value="Invoke"></TD></TR>
    </TABLE>
    </form>
<?vsp
   }

  if ({?'operation'} is not null and {?'callit'} is not null)
  {
    declare hinfo, result, ver, pars1, _url any;
    declare xe, xps, pars any;
    wsdl := soap_wsdl();
    xe := xml_tree_doc (wsdl);
    _url := {?'url'};
    hinfo := WS.WS.PARSE_URI ({?'url'});

    if (xpath_eval (sprintf ('/definitions/binding/operation[@name="%s"]/operation[@style="document"]', {?'operation'}), xe) is null)
      {
        xps := sprintf ('/definitions/message[@name = \'%sRequest\']/part', {?'operation'});
      }
    else if (xpath_eval (sprintf ('/definitions/message[@name = \'%sRequest\']/part[@name="parameters"]', {?'operation'}), xe) is not null)
      {
        declare elm_name any;
        declare pos int;

        xps := sprintf ('/definitions/message[@name = \'%sRequest\']/part/@element', {?'operation'});
        elm_name := cast (xpath_eval (xps, xe) as varchar);
        pos := strrchr (elm_name, ':');
        if (pos is not null)
          {
            elm_name := subseq (elm_name, pos + 1, length (elm_name));
          }
        xps := sprintf ('/definitions/types/schema/element[@name = "%s"]//element', elm_name);
      }
    else
      {
        xps := sprintf ('/definitions/message[@name = \'%sRequest\']/part', {?'operation'});
      }
    pars := xpath_eval (xps, xe, 0);
    len := length (pars);
    inx := 0;
    pars1 := vector ();
    while (inx < len)
      {
      declare exit handler for sqlstate '*' {
        result := xml_tree_doc (sprintf ('<Error>
		      <Code>%V
		      </Code>
		      <Message>%V
		      </Message>
		      </Error>', __SQL_STATE, __SQL_MESSAGE));
	goto err;
      };
	 declare n, t, v, va varchar;
         n := xpath_eval ('@name', pars[inx], 1);
         t := xpath_eval ('@type', pars[inx], 1);
         n := cast (n as varchar); t := cast (t as varchar);
         if (t like 'http://www.w3.org/____/XMLSchema:%')
	   {
	     t := substring (t, length ('http://www.w3.org/____/XMLSchema:') + 1, length (t));
	     t := concat ('xsd:', t);
	   }
	 else if (strchr (t, ':') is not null and t not like 'xsd:%')
	   {
	     declare colon integer;
             colon := strrchr (t, ':');
             t := substring (t, colon + 1, length (t));
	     t := concat ('s', t);
	   }
         v := get_keyword (n, params);
	 if (t like '_:ArrayOf%')
	   {
             v := replace (v, '\r\n', '\n');
             va := split_and_decode (v, 0, '\0\0\n');
	     pars1 := vector_concat (pars1, vector (n, va));
	   }
	 else if (t like '_:%')
	   {
	     declare r, struct, rstr any;
	     declare i, l integer;
             v := replace (v, '\r\n', '\n');
             va := coalesce (split_and_decode (v, 0, '\0\0\n='), vector ());
             t := substring (t, 3, length (t));
             xps :=
        sprintf ('/definitions/types/schema/complexType[@name = ''%s'']/*/element/@name', t);
             struct := xpath_eval (xps, xe, 0);
             i := 0; l := length (struct);
	     rstr := vector (composite(), '<soap_box_structure>');
	     while (i < l)
	       {
		 declare part nvarchar;
                 part := get_keyword (struct[i], va);
                 part := charset_recode (part,'UTF-8','_WIDE_');
                 rstr := vector_concat (rstr, vector (cast (struct[i] as varchar), part));
                 i := i + 1;
	       }
	     pars1 := vector_concat (pars1, vector (n, rstr));
	   }
	 else if (t like '%:dateTime')
	   {
             v := charset_recode (v,'UTF-8','_WIDE_');
	     v := cast (v as varchar);
	     v := cast (v as datetime);
	     pars1 := vector_concat (pars1, vector (n, v));
	   }
	 else
	   {
             v := charset_recode (v,'UTF-8','_WIDE_');
	     pars1 := vector_concat (pars1, vector (n, v));
	   }
         inx := inx + 1;
      }

    ver := 11;
    {
      declare exit handler for sqlstate '*' {
        result := xml_tree_doc (sprintf ('<Error>
		      <Code>%V
		      </Code>
		      <Message>%V
		      </Message>
		      </Error>', __SQL_STATE, __SQL_MESSAGE));
	goto err;
      };
      if (atoi (cfg_item_value (virtuoso_ini_path(), 'HTTPServer', 'ServerThreads')) < 2)
	{
	    result := xml_tree_doc (sprintf ('<Error>
			  <Code>%V
			  </Code>
			  <Message>%V
			  </Message>
			  </Error>', '42000', 'At least two HTTP threads must be available'));
	    goto err;
	}
      else
	{
          result := DB.DBA.SOAP_CLIENT (url=>_url, operation=>{?'operation'}, parameters=>pars1, version=>ver);
	}
    }

    if (ver = 11)
      {
	if (result[0][0] <> ' root')
	  result := vector (vector(' root'), result);
        result := xml_tree_doc (result);
      }
    else
      {
        result := xml_tree_doc (sprintf ('<Error>
		      <Code>%V
		      </Code>
		      <Message>%V
		      </Message>
		      </Error>', ver[1], ver[2]));
      }
err:;
    declare ses any;
    ses := xslt ('__soap_vsmx', result, vector ('service', {?'operation'}));
    http_value (ses);
  }

?>
</TD></TR></TABLE>
</DIV>
<DIV class="foot"><SPAN class="foot">Virtuoso Universal Server <?=sys_stat('st_dbms_ver')?> - Copyright&copy; 1999-2004 OpenLink Software.</SPAN></DIV>
 </BODY>
</HTML>
<?vsp
}
;

--!AFTER
xslt_sheet ('__soap_vsmx', xml_tree_doc('<?xml version="1.0"?>
     <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
      <xsl:output method="html" indent="yes" encoding="UTF-8" />
      <xsl:param name="service" select="''''" />
      <xsl:param name="ret_uri" select="''services.vsmx''" />
      <xsl:template match="/">
      <H3>Response</H3>
        <BR />
	<DIV class="response"><xsl:apply-templates select="*">
	  <xsl:with-param name="level">1</xsl:with-param></xsl:apply-templates></DIV>
      </xsl:template>

      <xsl:template match="*"><xsl:param name="level" />
	  <DIV class="details">
	    <SPAN><xsl:attribute name="class">level<xsl:value-of select="$level" /></xsl:attribute>
	      <xsl:value-of select="local-name()"/>:</SPAN>
	    <xsl:if test="$level > 1">
	    <SPAN class="data"><xsl:value-of select="text()"/>
	      <xsl:if test="@*">
	        <BR /><TABLE border="0" cellpadding="0" cellspacing="2">
	        <xsl:for-each select="@*">
	         <xsl:if test="(namespace-uri(.) != ''urn:schemas-microsoft-com:datatypes'')
		   and (namespace-uri(.) != ''http://www.w3.org/2001/XMLSchema-instance'')
		   and (namespace-uri(.) != ''http://schemas.xmlsoap.org/soap/encoding/'')
		   and (namespace-uri(.) != ''urn:schemas-openlink-com:xml-sql'')">
	            <TR><TD class="attribname"><xsl:value-of select="local-name()" />=</TD>
		      <TD class="attrib">"<xsl:value-of select="." />"</TD></TR>
	         </xsl:if>
	        </xsl:for-each>
	        </TABLE>
              </xsl:if>
	    </SPAN>
	    </xsl:if>
            <xsl:apply-templates select="*">
	      <xsl:with-param name="level"><xsl:value-of select="$level+1" /></xsl:with-param>
	    </xsl:apply-templates>
	  </DIV>
	</xsl:template>
    </xsl:stylesheet>')
)
;

create procedure WSDL_EXPAND (in _base_url any, in rsv any, inout schem any, inout defs any, inout ret any)
{
  declare idx, len, idx1, len1, use_cache integer;
  declare _location, _what varchar;
  declare _new, _import, _base, sch, t1, t2 any;

  if (not isarray (schem)) schem := vector ();
  if (not isarray (defs))  defs := vector ();
  if (not rsv is NULL)  _base_url := WS.WS.EXPAND_URL (_base_url, rsv);

  use_cache := 0;

  _base := WSDL_GET (_base_url, use_cache);

  if (rsv is NULL)  ret := _base;

  sch := xpath_eval ('/definitions/import', _base, 0);

  if (length (t1 := xpath_eval ('/definitions/types/schema', _base, 0)) > 0) schem := vector_concat (t1, schem);
  if (length (t2 := xpath_eval ('/definitions', _base, 0)) > 0) defs := vector_concat (defs, t2);

  idx := 0; len := length (sch);
  while (idx < len)
    {
      _location := cast (xpath_eval ('@location', sch[idx], 1) as varchar);
      _import := WSDL_GET (WS.WS.EXPAND_URL (_base_url, _location), use_cache);
      _new := xpath_eval ('/definitions/import', _import, 0);
      if (length (t1 := xpath_eval ('/definitions/types/schema', _import, 0))>0) schem := vector_concat (schem, t1);
      if (length (t2 := xpath_eval ('/definitions', _import, 0)) > 0) defs := vector_concat (defs, t2);
      len1 := length (_new); idx1 := 0;
      if (length (_new) > 0)
        {
           while (idx1 < len1)
             {
		_what := cast (xpath_eval ('@location', _new[0], 1) as varchar);
		_base_url := WS.WS.EXPAND_URL (_base_url, _location);
		WSDL_EXPAND (_base_url, _what, schem, defs, ret);
                idx1 := idx1 + 1;
             }
        }
      idx := idx + 1;
    }
}
;


--!AWK PUBLIC
create procedure
DB.DBA.SOAP_WSDL_IMPORT (in url varchar, in mode_wsdl integer := 1, in wire_dump integer := 0, in drop_module integer := 0)
{
  declare wsdl, xp, xt, uri, hinfo, sch, ret, pt any;
  declare i, l, i1, l1, is_literal integer;
  declare err, name, tns, mname, stmt, transport varchar;
  declare port_name, port_name_last any;
  declare tt, dmod varchar;

  WSDL_EXPAND (url, NULL, sch, pt, wsdl);

  i1 := 0; l1 := length (sch);
  while (i1 < l1)
    {
      xp := xpath_eval ('complexType', sch[i1], 0);
      tns := xpath_eval ('@targetNamespace', sch[i1], 1);
      if (tns is not null)
	{
	  tns := cast (tns as varchar);
	  tns := concat (tns, ':');
	}
      else
	 tns := '';

      i := 0; l := length (xp);
      while (i < l)
	{
	  xt := xslt ('http://local.virt/soap_sch', xp[i]);
	  err := xpath_eval ('string(//@error)', xt, 1);
	  err := cast (err as varchar);
	  if (err <> '')
	    {
	      rollback work;
	      signal ('22023', err, 'SODT1');
	    }
	  name := cast(xpath_eval ('string(/complexType/@name)', xt, 1) as varchar);
	  if (not exists (select 1 from DB.DBA.SYS_SOAP_DATATYPES where SDT_NAME = concat (tns, name) and SDT_TYPE = 0))
	    {
	      insert soft DB.DBA.SYS_SOAP_DATATYPES (SDT_NAME,SDT_SCH,SDT_TYPE) values (concat(tns, name), xt, 0);
	      __soap_dt_define (concat(tns, name), xt);
	    }
	  i := i + 1;
	}
      xp := xpath_eval ('element', sch[i1], 0);
      i := 0; l := length (xp);
      while (i < l)
	{
          xt := xslt ('http://local.virt/soap_sch', xp[i], vector ('target_Namespace', rtrim(tns, ':')));
	  err := xpath_eval ('string(//@error)', xt, 1);
	  err := cast (err as varchar);
	  if (err <> '')
	    {
	      rollback work;
	      signal ('22023', err, 'SODT1');
	    }
	  name := cast(xpath_eval ('string(/element/@name)', xt, 1) as varchar);
	  if (not exists (select 1 from DB.DBA.SYS_SOAP_DATATYPES where SDT_NAME = concat (tns, name) and SDT_TYPE = 1))
	    {
	      insert soft DB.DBA.SYS_SOAP_DATATYPES (SDT_NAME,SDT_SCH,SDT_TYPE) values (concat(tns, name), xt, 1);
	      __soap_dt_define (concat(tns, name), xt, NULL, 1);
	    }
	  -- type of elements
	  {
	    declare cmpl, cname, cname2,  sch2 varchar;
	    cmpl := xpath_eval (sprintf ('element[%d]/complexType[*]', (i+1)), sch[i1], 1);
	    -- must test for child elements
	    if (cmpl is not null)
	      {
		declare name1 varchar;
                name1 := cast(xpath_eval (sprintf ('string(element[%d]/@name)' , (i+1)), sch[i1], 1) as varchar);
		cname := sprintf ('elementType__%s', name1);
		if (tns is null or tns = '')
		  cname2 := cname;
		else
		  cname2 := sprintf ('%s%s', tns, cname);
                sch2 := xslt ('http://local.virt/soap_sch', cmpl,
			  vector ('type_name', cname, 'target_Namespace', rtrim(tns, ':')));
		__soap_dt_define (cname2, sch2, sch2, 0);
		insert replacing DB.DBA.SYS_SOAP_DATATYPES (SDT_NAME,SDT_SCH, SDT_TYPE) values (cname2, sch2, 0);
	      }
	  }
	  i := i + 1;
	}
      i1 := i1 + 1;
    }
  declare extens any;
  declare ns_ext nvarchar;
  extens := xpath_eval ('[xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/"] //*[@wsdl:required = "true"]', wsdl, 0);
  i1 := 0; l1 := length (extens);
  while (i1 < l1)
    {
      ns_ext := xpath_eval ('namespace-uri(.)', extens[i1], 1);
      if (ns_ext <> N'http://schemas.xmlsoap.org/wsdl/soap/')
	{
	  rollback work;
          signal ('22023', 'Not supported extensibility element', 'SODT2');
	}
      i1 := i1 + 1;
    }

  -- PL module generation
  mname := cast (xpath_eval ('/definitions/service/@name', wsdl, 1) as varchar);
  uri := cast (xpath_eval ('[xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"] /definitions/service/port/soap:address/@location', wsdl, 1) as varchar);
  hinfo := WS.WS.PARSE_URI (uri);

  stmt := concat ('CREATE MODULE ', DB.DBA.SYS_ALFANUM_NAME (mname), ' {\r\n');
  dmod := concat ('DROP MODULE ', DB.DBA.SYS_ALFANUM_NAME (mname));
  ret := vector (mname);
  i1 := 0; l1 := length (pt);
  while (i1 < l1)
    {
      if (not port_name is NULL or port_name <> 0) port_name_last := port_name;
      port_name := cast (xpath_eval ('/definitions/portType/@name', pt[i1], 1) as varchar);
      if (port_name is NULL) goto new_loop;
      if ((port_name_last <> port_name) and
          (port_name_last <> '0') and
          (port_name_last <> 0) and
          (not port_name_last is NULL))
            port_name := port_name_last;
      tt := sprintf ('[xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"] /definitions/binding[@type like ''%s'']/soap:binding/@transport', concat ('%', port_name));
      if (transport := FIND_WSDL (pt, tt) is NULL) goto new_loop;
      tt := sprintf ('/definitions/portType[@name like ''%s'']/operation', port_name);
      xp := xpath_eval (tt, pt[i1], 0);
      i := 0; l := length (xp);
      while (i < l)
	{
	  declare i_message, o_message, i_parm, o_parm any;
	  declare o_name, o_ns, soap_action, _ins, _out varchar;
	  declare colon, j, k integer;
	  declare ppars, res_pars varchar;
	  declare encoded any;

	  o_name := cast (xpath_eval ('@name', xp[i], 1) as varchar);

	  i_message := cast (xpath_eval ('input/@message', xp[i], 1) as varchar);
	  o_message := cast (xpath_eval ('output/@message', xp[i], 1) as varchar);

	  colon := strrchr (i_message, ':');
	  if (colon is not null)
	    i_message := substring (i_message, colon+2, length (i_message));
	  colon := strrchr (o_message, ':');
	  if (colon is not null)
	    o_message := substring (o_message, colon+2, length (o_message));

          tt := sprintf ('/definitions/message[@name like ''%s'']/part', concat ('%', i_message));
          i_parm := FIND_WSDL(pt ,tt);

          tt := sprintf ('/definitions/message[@name like ''%s'']/part', concat ('%', o_message));
          o_parm := FIND_WSDL(pt ,tt);

          ppars := ''; res_pars := vector ();
	  _ins := ''; _out := '';
--
--        INPUTS
--
          declare have_in_par integer;
          j := 0; k := length (i_parm); have_in_par := 0;
	  is_literal := 0;
	  while (j < k)
	    {
	      declare par, typ varchar;
	      par := cast (xpath_eval ('@name', i_parm[j]) as varchar);
	      typ := cast (xpath_eval ('@type', i_parm[j]) as varchar);
	      if (typ is NULL)
                {
                  typ := cast (xpath_eval ('@element', i_parm[j]) as varchar);
	  	  --colon := strchr (typ, ':');
	  	  --if (colon is not null) typ := substring (typ, colon+2, length (typ));
		  --tt := sprintf ('/definitions/types/schema/element[@name = ''%s'']/@type', typ);
                  --if (typ := FIND_WSDL(pt ,tt) is NULL)  goto new_loop;
	          --typ := cast (typ[0] as varchar);
		  is_literal := 1;
	 	}
	      if (j > 0)
		{
		  _ins := concat (_ins, ',');
		  ppars := concat (ppars, ',');
		}
	      _ins := concat (_ins, 'IN _', par, ' any __soap_type ''',typ ,'''');
	      ppars := concat (ppars, sprintf ('vector(''%s'', ''%s''), _', par, typ), par);
              res_pars := vector_concat (res_pars, vector (concat ('_', par), typ));
	      j := j + 1;
	    }
          have_in_par := j;
--
--        OUTPUTS
--
	  j := 0; k := length (o_parm);
	  while (j < k)
	    {
	      declare par, typ varchar;
	      par := cast (xpath_eval ('@name', o_parm[j]) as varchar);
	      typ := cast (xpath_eval ('@type', o_parm[j]) as varchar);
	      if (j > 0 or have_in_par > 0)
		{
		  _out := concat (_out, ',');
		}
	      _out := concat (_out, 'OUT _', par ,' any __soap_type ''',typ ,'''');

	      j := j + 1;
	    }

	  stmt := concat (stmt, '\r\n PROCEDURE ', o_name, ' (', _ins);

	  ret := vector_concat (ret, vector(o_name, res_pars));
	  o_ns := cast (xpath_eval (
		    sprintf ('/definitions/binding/operation[@name = ''%s'']/input/body/@namespace',
		      o_name), wsdl, 1) as varchar);
	  soap_action :=
		    cast (xpath_eval (
			  sprintf ('/definitions/binding/operation[@name = ''%s'']/operation/@soapAction',
			    o_name), wsdl, 1) as varchar);

          encoded := cast (xpath_eval (
                    sprintf ('[xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"] /definitions/binding/operation[@name = ''%s'']/input/soap:body/@use',
                    o_name), wsdl, 1) as varchar);

	  if (encoded is not null and encoded = 'literal')
	    {
	      encoded := 1;
              is_literal := 1;
	    }
	  else
	    encoded := 0;

          if (wire_dump)
            encoded := encoded + 2;

	  if (soap_action is null or soap_action = '')
	    {
	      soap_action := '""';
	    }
	  else
	    {
              soap_action := concat ('"',trim (soap_action, '" '),'"');
	    }

	  if (length (o_ns))
	    o_ns := sprintf ('''%s''', o_ns);
	  else
	    o_ns := 'NULL';

	  soap_action := sprintf ('''%s''', soap_action);

          if (not mode_wsdl)
            stmt := concat (stmt, _out);

	  if (is_literal)
	    stmt := concat (stmt, ') \n returns any __soap_doc ''__VOID__''\n');
	  else
	    stmt := concat (stmt, ') \n returns any __soap_type ''__VOID__''\n');

          if (mode_wsdl)
            {
	       stmt := concat (stmt, '{\n  declare res, ver any;\n  ver:=11;\n  ');
	       stmt := concat (stmt,
                   sprintf ('res := soap_call_new (''%s'',''%s'',\n    %s, ''%s'', vector (%s), ver, NULL, NULL, %s, %d);\n',
		   hinfo[1], hinfo[2], o_ns, o_name, ppars, soap_action, encoded));
	       stmt := concat (stmt, '  if (ver <> 11) signal (ver[1], ver[2]); \r\n return res; };  ');
	    }
	  else
	    {
              stmt := concat (stmt, '{ \n declare ret any; \n return ret; \n} ;\n');
	    }

	  i := i + 1;
	}
new_loop:
       i1 := i1 + 1;
    }
  stmt := concat (stmt, '  \r\n} \n');
--dbg_obj_print (stmt);
  if (length (stmt) > 7)
    {
      if (drop_module)
	{
	  declare st1, ms1 varchar;
          st1 := '00000';
	  exec (dmod, st1, ms1);
	}
      DB.DBA.EXEC_STMT (stmt, 0);
    }
  else
    ret := NULL;
  return ret;
}
;

create procedure FIND_WSDL (in _all any, in _what varchar)
{
  declare idx, len integer;
  declare ret any;

  len := length (_all);
  idx := 0;

  while (idx < len)
    {
       ret := xpath_eval (_what, _all[idx], 0);
       if (length (ret) > 0)
         return ret;
       idx := idx + 1;
    }

  return NULL;
}
;


create procedure WSDL_GET (in uri varchar, in _mode integer)
{
  declare _hdr, _ret any;

--  _ret := http_get (uri, _hdr);
  _ret := xml_uri_get (uri, '');
  _ret := xml_tree_doc (_ret);
  return _ret;
}
;


--!AWK PUBLIC
create procedure SQL_PROCEDURE_COLUMNSW (
    in qual varchar,
    in owner varchar,
    in name varchar,
    in col varchar,
    in casemode integer,
    in is_odbc3 integer
    )
{
  declare PROCEDURE_CAT, PROCEDURE_SCHEM, PROCEDURE_NAME, COLUMN_NAME, TYPE_NAME, REMARKS nvarchar;
  declare COLUMN_SIZE, BUFFER_LENGTH integer;
  declare COLUMN_TYPE, DATA_TYPE, DECIMAL_DIGITS, NUM_PREC_RADIX, NULLABLE smallint;

  declare COLUMN_DEF, IS_NULLABLE nvarchar;
  declare SQL_DATA_TYPE, SQL_DATETIME_SUB smallint;
  declare CHAR_OCTET_LENGTH, ORDINAL_POSITION integer;


  result_names (PROCEDURE_CAT, PROCEDURE_SCHEM, PROCEDURE_NAME, COLUMN_NAME,
      COLUMN_TYPE, DATA_TYPE, TYPE_NAME, COLUMN_SIZE, BUFFER_LENGTH,
      DECIMAL_DIGITS, NUM_PREC_RADIX, NULLABLE, REMARKS,
      COLUMN_DEF, SQL_DATA_TYPE, SQL_DATETIME_SUB, CHAR_OCTET_LENGTH, ORDINAL_POSITION, IS_NULLABLE);

  declare full_name varchar;
  declare inx, sz integer;
  declare cols, elt any;

  full_name := name;
  if (owner is not null)
      full_name := concat (owner, '.', full_name);
  else if (qual is not null)
      full_name := concat ('.', full_name);

  if (qual is not null)
    full_name := concat (qual, '.', full_name);

  for
     select
       P_NAME
     from DB.DBA.SYS_PROCEDURES
     where
       either (casemode,
	   charset_recode (upper (charset_recode (P_NAME, 'UTF-8', '_WIDE_')), '_WIDE_', 'UTF-8'),
	   P_NAME) like
       either (casemode, charset_recode (upper (charset_recode (full_name, 'UTF-8', '_WIDE_')), '_WIDE_', 'UTF-8'), full_name)
       and __proc_exists (P_NAME) is not null
  do
    {
      cols := procedure_cols (P_NAME);
      if (cols)
	{
	  sz := length (cols);
	  inx := 0;
	  while (inx < sz)
	    {
	      elt := aref (cols, inx);
	      if (either (casemode, upper (aref (elt, 3)), aref (elt, 3)) like
		  either (casemode, upper (col), col))
		{
		  result (
		     charset_recode (aref (elt, 0), 'UTF-8', '_WIDE_'),
		     charset_recode (aref (elt, 1), 'UTF-8', '_WIDE_'),
		     charset_recode (aref (elt, 2), 'UTF-8', '_WIDE_'),
		     charset_recode (aref (elt, 3), 'UTF-8', '_WIDE_'),
		     aref (elt, 4),
		     either (is_odbc3, dv_to_sql_type3 (aref (elt, 5)), dv_to_sql_type (aref (elt, 5))),
		     dv_type_title (aref (elt, 5)),
		     aref (elt, 7),
		     aref (elt, 7),
		     aref (elt, 6),
		     10,
		     aref (elt, 8),
		     NULL,

		     NULL,
		     either (is_odbc3, dv_to_sql_type3 (aref (elt, 5)), dv_to_sql_type (aref (elt, 5))),
		     NULL,
		     aref (elt, 7),
		     aref (elt, 9),
		     either (aref (elt, 8), 'YES', 'NO')
		     );
		}
	      inx := inx + 1;
	    }
	}
    }
}
;

-- /* XML template processing */

create procedure
DB.DBA.__XML_TEMPLATE (in path any, in params any, in lines any, in enc any := null)
{
  declare xt any;
  declare xslt, f varchar;
  --set http_charset = 'UTF-8';
  f := concat (http_root (), http_physical_path ());
  if ({?'template'} is not null and not isstring (file_stat (f, 3)))
    xt := xtree_doc({?'template'}, 0);
  else
    xt := xtree_doc(file_to_string (f), 0);

  if (enc is not null)
    {
      if (is_http_ctx ())
	{
	  set http_charset=enc;
	}
      else
        xml_tree_doc_encoding (xt, enc);
    }
  else
    enc := current_charset ();


  __set_user_id (http_map_get ('vsp_uid'));
  xslt := xml_template (xt, params);


  if (xslt is not null)
    {
      if (xslt = '__xml_template_default')
        xslt := 'precompiled:__xml_template_default';
      else if ({?'__base_url'} is not null)
        xslt := WS.WS.EXPAND_URL ({?'__base_url'}, xslt);
      else
        xslt := WS.WS.EXPAND_URL (concat ('file:', http_physical_path ()), xslt);
      http_xslt (xslt);
    }

  if ({?'contenttype'} is not null)
    http_header (sprintf ('Content-type: %s; charset="%s"\r\nCache-Control: no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: Thu, 01 Dec 1994 01:02:03 GMT\r\n', {?'contenttype'}, enc));
  else if (xslt is null)
    http_header (sprintf ('Content-type: text/xml; charset="%s"\r\nCache-Control: no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: Thu, 01 Dec 1994 01:02:03 GMT\r\n', enc));
  if ({?'content-filename'} is not null)
    {
      http_header (concat (http_header_get (), sprintf ('Content-Disposition: inline; filename="%s"\r\n', {?'content-filename'})));
    }
  __pop_user_id ();
}
;

--!AFTER
create procedure vt_upgrade_text_index (
    in tb varchar,
    in is_xml integer := -1,
    in _func integer :=  -1,
    in _lang varchar := '*ini*',
    in _enc varchar := '*ini*')
{
  declare text_id_col, kn, func, ufunc, col, obd, vtlog_suff, tb_suff varchar;
  declare t1, t2, t3 any;
  declare f_xml integer;

  if (_lang is null)
    _lang := '*ini*';

  if (_enc is null)
    _enc := '*ini*';

  tb := complete_table_name ((tb), 1);

  vtlog_suff := concat (name_part (tb, 0), '_', name_part (tb, 1), '_', name_part (tb, 2));
  tb_suff := DB.DBA.SYS_ALFANUM_NAME (vtlog_suff);


  if (not exists (select 1 from DB.DBA.SYS_KEYS where 0 = casemode_strcmp (KEY_TABLE,  tb)))
    {
      signal ('42S02', sprintf ('No table ''%s'' in create text index', tb), 'FT021');
    }

  if (not exists (select 1 from DB.DBA.SYS_VT_INDEX where 0 = casemode_strcmp (VI_TABLE,  tb)))
    {
      signal ('42S01', 'Text index is not defined for table', 'FT022');
    }

  select  VI_COL, VI_ID_COL, deserialize(VI_OFFBAND_COLS), VI_LANGUAGE, VI_ENCODING
      into col, text_id_col, obd, _lang, _enc from SYS_VT_INDEX where VI_TABLE = tb;

  func := null;
  ufunc := null;

  if (_func = 1 or _func < 0)
    {
       func := coalesce ((select P_NAME from DB.DBA.SYS_PROCEDURES where
		   0 =  casemode_strcmp (P_NAME, sprintf ('%s_%s_INDEX_HOOK', tb, col))), NULL);
       if (func is null)
         func := __proc_exists (sprintf ('%s_%s_INDEX_HOOK', tb, col));

       ufunc := coalesce ((select P_NAME from DB.DBA.SYS_PROCEDURES where
		     0 = casemode_strcmp (P_NAME, sprintf ('%s_%s_UNINDEX_HOOK', tb, col))), NULL);

       if (ufunc is null)
         ufunc := __proc_exists (sprintf ('%s_%s_UNINDEX_HOOK', tb, col));
    }

  if (_func < 0 and (func is null or ufunc is null))
    {
      func := null;
      ufunc := null;
    }

  if (_func = 1 and (func is null or ufunc is null))
    signal ('37000', 'The hook functions are not available.', 'FT023');

  whenever not found goto eof;
  select coalesce (T_TEXT, blob_to_string (T_MORE)) into t1 from SYS_TRIGGERS
    where T_TABLE = tb and T_NAME like concat ('%.', tb_suff, '_VTI_log');
  select coalesce (T_TEXT, blob_to_string (T_MORE)) into t2 from SYS_TRIGGERS
    where T_TABLE = tb and T_NAME like concat ('%.', tb_suff, '_VTU_log');
  select coalesce (T_TEXT, blob_to_string (T_MORE)) into t3 from SYS_TRIGGERS
    where T_TABLE = tb and T_NAME like concat ('%.', tb_suff, '_VTD_log');
eof:

  f_xml := 0;
  if (isstring (t1) and strstr (t1, '(1 = 1)') is not null)
    f_xml := f_xml + 1;
  if (isstring (t2) and strstr (t2, '(1 = 1)') is not null)
    f_xml := f_xml + 1;
  if (isstring (t3) and strstr (t3, '(1 = 1)') is not null)
    f_xml := f_xml + 1;

  if (_func < 0 and isstring (t1) and isstring (func) and strstr (t1, name_part (func, 2)) is null)
    {
      func := NULL;
      ufunc := NULL;
    }
  if (_func < 0 and isstring (t3) and isstring (ufunc) and strstr (t3, name_part (ufunc, 2)) is null)
    {
      func := NULL;
      ufunc := NULL;
    }

  if (is_xml < 0 and f_xml = 3)
    is_xml := 1;
  else if (is_xml < 0)
    is_xml := 0;

  if (tb = 'DB.DBA.MAIL_MESSAGE' or
      tb = 'DB.DBA.NEWS_MSG' or
      tb = 'WS.WS.SYS_DAV_RES')
    is_xml := 2;

  if (_lang is null)
    _lang := '*ini*';

  if (_enc is null)
    _enc := '*ini*';
  declare hits_proc varchar;
  hits_proc := NULL;
  for select coalesce (P_TEXT, blob_to_string (P_MORE)) as txt from DB.DBA.SYS_PROCEDURES
    where 0 = casemode_strcmp (P_NAME, concat (name_part (tb,0),'.',name_part(tb,1),'.VT_HITS_', name_part (tb, 2))) do
      {
        hits_proc := txt;
      }

  --dbg_obj_print (tb, ' is_xml: ', is_xml, ' hooks: ', func, ' & ', ufunc, _lang, _enc);
  DB.DBA.vt_free_text_proc_gen (tb, text_id_col, col, is_xml, obd, func, ufunc, _lang, _enc);
  DB.DBA.vt_create_update_log (tb, is_xml, 1, obd, func, ufunc, _lang, _enc, 0);
  if (hits_proc is not null)
    DB.DBA.execstr (hits_proc);
  return 0;
}
;

--!AFTER
create procedure
VT_INDEX_UPGRADE ()
{
  declare st, msg varchar;
  declare ver, db_ver any;
  ver := registry_get ('__FTI_VERSION__');
  db_ver := sys_stat ('db_ver_string');
  db_ver := atoi (replace (db_ver, '.', ''));
  if (not isstring (ver))
    ver := 0;
  else
    ver := atoi (ver);

  if (ver > 2204)
    return;

  registry_set ('__FTI_VERSION__', '2205');

  if (db_ver > 250)
    return;

  log_message ('Upgrading the old type text indexes');
  for select VI_TABLE from DB.DBA.SYS_VT_INDEX do
    {
      declare tablename, vtlog_suff,q,o varchar;
      tablename := VI_TABLE;
      q := name_part (tablename, 0);
      o := name_part (tablename, 1);
      tablename := complete_table_name ((tablename), 1);
      vtlog_suff := concat (name_part (tablename, 0), '_', name_part (tablename, 1), '_', name_part (tablename, 2));
      if ((not exists
	  (select 1 from SYS_COLS where \COLUMN = 'VT_GZ_WORDUMP' and \TABLE =
	   sprintf ('%s.%s.VTLOG_%s', q, o, vtlog_suff)))
       or (not exists
          (select 1 from SYS_COLS where \COLUMN = 'VT_OFFBAND_DATA' and \TABLE =
	   sprintf ('%s.%s.VTLOG_%s', q, o, vtlog_suff))))
        {
          log_message (
          sprintf ('The text index on table %s can''t be upgraded, please drop the index and recreate', VI_TABLE));
	}
      else
	{
--          log_message (sprintf ('Upgrading the old type text indexes on %s', VI_TABLE));
          vt_upgrade_text_index (VI_TABLE);
	}
    }
}
;


--!AFTER
VT_INDEX_UPGRADE ()
;

--!AWK PUBLIC
create procedure
DB.DBA.XQ_TEMPLATE (inout q varchar, inout ctx varchar, inout ses any, inout map_schema any)
{
  declare res, qry, uri, doc any;
  declare i, l integer;
  if (isstring (map_schema))
    qry := sprintf ('for $r in xmlview("%s")%s return $r', map_schema, q);
  else
    qry := q;

  if (isstring (ctx) and length (ctx))
    {
      uri := DB.DBA.XML_URI_RESOLVE_LIKE_GET ('', ctx);
      doc := DB.DBA.XML_URI_GET ('', uri);
      doc := xtree_doc (doc, 0, uri);
    }
  else
    {
      doc := xper_doc('<blank/>', 0, ctx);
    }

  res := xquery_eval (qry, doc, 0);
  i := 0; l := length (res);
  while (i<l)
    {
      http_value (res[i], NULL, ses);
      i := i + 1;
    }
}
;

--!AWK PUBLIC
create procedure
DB.DBA.SQLX_OR_SPARQL_TEMPLATE (inout q varchar, inout params any, inout ses any, inout q_type any)
{
  declare h, res, qry any;
  qry := q;

  if (q_type)
    {
      declare arr, _text, decl, i, l any;
      _text := substring (qry, 7, length (qry));
      arr := sparql_lex_analyze (_text);
      l := length (arr)-2;
      for (i := 0; i < l; i := i + 1)
        {
	  declare elm any;
	  if (isstring (arr[i][2]) and isstring (arr[i+1][2]) and isstring (arr[i+2][2]))
	    {
	      elm := lower (arr[i][2]);
	      if (elm = 'define' and lower (arr[i+1][2]) = 'output:format')
		{
		  if (upper (arr[i+2][2]) = '"RDF/XML"')
		    goto done;
		  else
		    signal ('22023', 'The output:format must be RDF/XML');
		}
	    }
	}
      qry := 'SPARQL define output:format "RDF/XML" ' || _text;
      done:;
    }

  exec (qry,  null, null, params, 0, null, null, h);
  while (0 = exec_next(h, null, null, res))
    {
      if (isarray (res) and length (res))
	{
	  foreach (any elm in res) do
	    {
	      if (isentity (elm))
		http_value (elm, null, ses);
	      else if (isstring (elm) or __tag (elm) = 185)
		http (elm, ses);
	    }
	}
    }
  exec_close (h);
  return;
}
;

--!AFTER
xslt_sheet ('__xml_template_default', xml_tree_doc (xml_tree(
'<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0" >
<xsl:output method="html"/>
<xsl:template match="/">
  <HTML>
    <title>Search results</title>
    <BODY>
     <H4>Search results</H4>
     <TABLE BOREDER="0">
      <xsl:apply-templates select="*" />
     </TABLE>
    </BODY>
  </HTML>
</xsl:template>
<xsl:template match="resource">
  <TR>
   <TD><b>Document:</b></TD><TD><A><xsl:attribute name="HREF"><xsl:value-of select="@name"/></xsl:attribute><xsl:value-of select="@name"/></A></TD>
  </TR>
  <TR>
   <TD><b>Last Modified:</b></TD>
   <TD><xsl:value-of select="substring (@modified ,1, 19)"/></TD>
  </TR>
  <TR>
   <TD><b>Size:</b></TD>
   <TD><xsl:value-of select="@length"/> bytes</TD>
  </TR>
  <TR>
   <TD colspan="2">&nbsp;</TD>
  </TR>
</xsl:template>
</xsl:stylesheet>'))
)
;


create procedure
cov_store (in f varchar, in add_line integer := 0)
{
  declare i, l, i1, l1 integer;
  declare arr, arr1 any;
  declare result varchar;
  declare ses any;
  arr1 := pldbg_stats (NULL, add_line, null, 1);
  if (length (arr1) < 1)
    return NULL;
  ses := string_output ();
  http ('<?xml version="1.0" ?>\n<pl_stats>', ses);
  i1:=0; l1:=length(arr1);
  while (i1 < l1)
    {
      arr := arr1[i1];
      if (length (arr))
	{
          declare tag_name, udt_name any;
	  tag_name := 'proc';
          udt_name := '';
          if (length (arr[0]) > 5 and arr[0][5] is not null)
            {
              tag_name := 'method';
              udt_name := sprintf (' class="%V"', arr[0][5]);
            }
	  if (add_line)
	    result := sprintf ('\n\t<%s name="%V" calls="%08d" file="%V" lct="%d" time="%d" self="%d" %s>', tag_name, arr[0][0], arr[0][2], arr[0][1], arr[0][3], arr[0][4], arr[0][6], udt_name);
	  else
	    result := sprintf ('\n\t<%s name="%V" calls="%08d" file="%V" time="%d" self="%d" %s>', tag_name, arr[0][0], arr[0][2], arr[0][1], arr[0][4], arr[0][6], udt_name);
	  i := 0;
	  l := length (arr[1]);
	  while (i < l)
	    {
	      if (add_line)
	         result := concat (result, sprintf ('\n\t\t<line no="%06d" ctr="%06d"><![CDATA[%s]]></line>', arr[1][i][0], arr[1][i][1], replace(replace(arr[1][i][2], '"', ''''), ']]>', ']]>]]<![CDATA[>')));
	      else
	         result := concat (result, sprintf ('\n\t\t<line no="%06d" ctr="%06d" />', arr[1][i][0], arr[1][i][1]));
	      i := i + 1;
	    }
	  i := 0;
	  l := length (arr[2]);
	  while (i < l)
	    {
	      result := concat (result, sprintf ('\n\t\t<caller name="%V" ct="%06d" />', arr[2][i][0], arr[2][i][1]));
	      i := i + 1;
	    }
	  result := concat (result, sprintf('\n\t</%s>', tag_name));
          http (result, ses);
	}
      i1 := i1+ 1;
    }
  http ('</pl_stats>', ses);
  string_to_file (f, ses, -2);
}
;


create procedure
cov_load (in f varchar)
{
  declare rep varchar;
  declare xt any;
  declare xp any;
  declare i, j, k, l integer;
  if (not isstring (file_stat (f, 3)))
    return;
  rep := file_to_string (f);
  xt := xml_tree_doc (rep);
  xp := xpath_eval ('/pl_stats/proc|/pl_stats/method', xt, 0);
  i := 0; l := length (xp);
  while (i < l)
    {
      declare name, udt varchar;
      declare calls, tim, sel integer;
      declare lin, cal, res, lins, cals any;
      name := cast (xpath_eval ('@name',xp[i], 1) as varchar);
      udt := cast (xpath_eval ('@class',xp[i], 1) as varchar);
      calls := cast (xpath_eval ('@calls',xp[i], 1) as integer);
      tim := cast (xpath_eval ('@time',xp[i], 1) as integer);
      sel := cast (xpath_eval ('@self',xp[i], 1) as integer);
      if (tim is null) tim := 0;
      if (sel is null) sel := 0;
      lin := xpath_eval ('line', xp[i], 0);
      cal := xpath_eval ('caller', xp[i], 0);
      res := vector (vector (name, 'unnamed', calls, tim, udt, sel));
      j := 0; k := length (lin);
      lins := vector ();
      while (j < k)
        {
	  declare line_no, cnt integer;
          line_no := cast (xpath_eval ('@no',lin[j], 1) as integer);
          cnt := cast (xpath_eval ('@ctr', lin[j], 1) as integer);
          lins := vector_concat (lins, vector (vector (line_no, cnt)));
	  j := j + 1;
	}

      j := 0; k := length (cal);
      cals := vector ();
      while (j < k)
        {
	  declare cnt integer;
	  declare caller varchar;
          caller := cast (xpath_eval ('@name',cal[j], 1) as varchar);
          cnt := cast (xpath_eval ('@ct', cal[j], 1) as integer);
          cals := vector_concat (cals, vector (vector (caller, cnt)));
	  j := j + 1;
	}
      res := vector_concat (res, vector(lins), vector(cals));
      pldbg_stats_load (res);
      i := i + 1;
    }
}
;


create procedure
cov_report (in f varchar, in odir varchar)
{
  --no_c_escapes-
  declare r, s, xt, files, fls, xe any;
  declare i, l integer;
  if (odir not like '%/')
    odir := concat (odir, '/');
  xe := xml_tree_doc (file_to_string (f));
  xt := xpath_eval ('/pl_stats/*/@file', xe, 0);
  files := vector ();
  fls := '<files>';
  i := 0; l := length (xt);
  while (i < l)
    {
      declare elm varchar;
      elm := cast (xt[i] as varchar);
      if (not position (elm, files))
        {
	  files := vector_concat (files, vector (elm));
          fls := fls || sprintf ('<file name="%s"/>', elm);
        }
      i := i + 1;
    }
  fls := fls || '</files>';
  i := 0; l := length (files);
  while (i < l)
    {
      declare fname varchar;
      r := xslt ('http://local.virt/cov_report', xe, vector ('file_name', files[i]));
      s := string_output ();
      http_value (r, null, s);
      fname := files[i];
      fname := replace (fname, '\\', '/');
      if (strrchr (fname, '/') is not null)
	fname := subseq (fname, strrchr (fname, '/') + 1);
      string_to_file (concat(odir,fname,'.cov'), s, -2);
      i := i + 1;
    }
  r := xslt ('http://local.virt/cov_time', xe, vector ('files', xtree_doc (fls)));
  s := string_output ();
  http_value (r, null, s);
  string_to_file (concat(odir,'profile','.prof'), s, -2);
}
;

-- /* remote procedure wrappers */

create procedure
vd_remote_proc_wrapper (in _dsn varchar, in pro varchar, in dest varchar, in meta any, out state varchar, out msg varchar, in make_rset integer := 0, in descr varchar := '')
{
  declare pars any;
  declare q,o,n, par, typ, rname, _comment, stmt1, rcols, rcols1, rcols2, remote_st varchar;
  declare q1,o1,n1, cmn1, rset varchar;
  declare have_rset, posit, i, l integer;
  declare loop_str varchar;

  declare infos, dbms, driv any;
  infos := vector ();
  if (_dsn <> '')
    {
      whenever not found goto nfnd;
      select deserialize (DS_CONN_STR) into infos from DB.DBA.SYS_DATA_SOURCE where DS_DSN = _dsn;
nfnd:;
    }

  dbms := upper (get_keyword (17, infos, ''));
  driv := upper (get_keyword (6, infos, ''));

  q := name_part (dest, 0);
  o := name_part (dest, 1);
  n := name_part (dest, 2);

  _comment := coalesce (descr, '');

  if (_comment <> '')
    _comment := concat ('\-\-##', _comment, '');

  q1 := name_part (pro, 0);
  o1 := name_part (pro, 1);
  n1 := name_part (pro, 2);

  have_rset := 0;
  rset := ', {resultset 1000, ';
  stmt1 := sprintf ('create procedure "%I"."%I"."%I" (', q,o,n);
  rcols := ''; rcols1 := ''; rcols2 := ''; posit := 0;
  if (q1 = '')
    {
      if (dbms like '%ORACLE%' and (driv like 'MSORCL32.DLL%' or driv like 'OPLODBC.SO'))
        rname := concat (o1,'.',n1);
      else
        rname := quote_dotted (_dsn, concat (o1,'.',n1));
      remote_st := sprintf ('{call %s (', rname);
    }
  else
    {
      declare pro1 varchar;
      pro1 := pro;
      if (pro1 like '%;%')
        {
          declare semi integer;
          declare pro2, num2 varchar;
          semi := strrchr (pro, ';');
          pro2 := pro1; num2 := '';
          if (semi is not null)
            {
               pro2 := subseq (pro1, 0, semi);
               num2 := subseq (pro1, semi, length (pro1));
            }
           rname := quote_dotted (_dsn, pro2);
           rname := concat (rname, num2);
        }
      else
        rname := quote_dotted (_dsn, pro1);
      remote_st := sprintf ('{call %s (', rname);
    }

  declare br integer;
  if (isarray (meta))
    pars := meta;
  else
    pars := vector ();
  i := 0; l := length (pars); br := 0;
  while (i < l)
    {
      declare t, na, dt, st varchar;
      na := pars [i][1];
      t := pars [i][0];

      dt := pars [i][2];
      st := pars [i][3];

      if (t = 'RESULTSET' and dbms like '%ORACLE%')
	{
	  rset := concat (rset, na, ',');
          have_rset := 1;
          goto nexti;
	}

      if (t = 'RETURNS')
        {
	  br := 1;
	}
      else if (t <> 'RESULTSET')
	{
	  stmt1 := concat (stmt1, t, ' ', na, ' ', dt);
	  rcols := concat (rcols, na, ',');
	  if (t = 'IN')
            rcols1 := concat (rcols1, na, ',');
	  else
            rcols1 := concat (rcols1, sprintf ('vector (''%s'', ''%s'', 0, %s),',t,dt,na));
          if (t <> 'IN')
            rcols2 := concat (rcols2, na, sprintf (' := params[%d] ;', posit));
	  posit := posit + 1;
          remote_st := concat (remote_st, '?,');
	}
      if (st <> '')
	{
	  if (t <> 'RETURNS')
            stmt1 := concat (stmt1, ' __soap_type ''', st, '''');
	}
      if (t <> 'RETURNS')
        stmt1 := concat (stmt1, ',');
nexti:
      i := i + 1;
    }
  stmt1 := trim (stmt1, ', ');
  remote_st := trim (remote_st, ', ');

  if (have_rset)
    {
      rset := rtrim (rset, ', ');
      rset := concat (rset, '}');
      remote_st := concat (remote_st, rset);
    }

  remote_st := concat (remote_st, ')');
  if (remote_st like '%()')
    remote_st := trim (remote_st,')(');
  rcols := trim (rcols, ', ');

  rcols1 := rtrim (rcols1, ', ');

  if (make_rset)
    loop_str := '\n if (isarray (mdta) and isarray (dta)) { exec_result_names(mdta[0]);\ndeclare i, l integer;\ni := 0; l := length (dta);\n while(i<l) {\n   exec_result(dta[i]);\n   i:=i+1;\n } }';
  else
    loop_str := '\nreturn dta;';

  remote_st := remote_st || '}';

  stmt1 := concat (stmt1, sprintf ( ') returns any array array\n{ \n\-\-PL Wrapper for remote procedure\n%s\n\-\-"DSN:%s PROCEDURE:%s"\ndeclare dta, mdta any; \ndeclare params any; \nparams := vector (%s); \nset_user_id (''dba'');\nrexecute (%s, %s, NULL, NULL, params, 0, mdta, dta); \n%s\n%s\n}', _comment, _dsn, pro, rcols1, WS.WS.STR_SQL_APOS (_dsn), WS.WS.STR_SQL_APOS (remote_st), rcols2, loop_str));
  state := '00000';
  exec (stmt1, state, msg);
}
;


update SYS_COLS set COL_PREC = 2147483647 where COL_DTP = 125 and COL_PREC < 2147483647
;

create procedure EXEC_STMT (in stmt_text varchar, in mode integer)
{
   declare state, msg varchar;
   declare meta, res any;

   if (mode)
     return execstr (stmt_text);

   exec (stmt_text, state, msg, vector (), 100, meta, res);
}
;


--!AWK PUBLIC
create procedure RSTMTEXEC (in dsn varchar, in stmt varchar, in max_rows integer := 0, in params_array any := null)
{
  declare stmt_compilation, cursor_handle, curr_row any;
  declare row_ctr integer;

  rexecute (dsn, stmt, NULL, NULL, params_array, NULL, stmt_compilation, NULL, cursor_handle);

  if (not isarray (stmt_compilation))
    signal ('22023', 'The statement in RSTMTEXEC should have a resultset', 'VD086');

  exec_result_names (stmt_compilation[0]);

  row_ctr := 0;
  if (max_rows >= 0)
    {
      while (0 = rnext (cursor_handle, curr_row))
	{
	  if (isarray (curr_row))
	    exec_result (curr_row);
	  row_ctr := row_ctr + 1;
	  if (max_rows > 0 and row_ctr >= max_rows)
	    goto done;
	}
    }
done:
  rclose (cursor_handle);
}
;


create procedure WS.WS.DIR_INDEX_MAKE_XML (inout _sheet varchar)
{
   declare dirarr, filearr, fsize, ret_xml any;
   declare curdir, dirname, root, start_from, modt varchar;
   declare ix, len, flen, rflen, mult integer;
   fsize := vector ('b','K','M','G','T');
   curdir := concat (http_root (), http_physical_path ());
   start_from := http_path ();
   root := http_root ();
   ret_xml := string_output ();
   dirarr := sys_dirlist (curdir, 0, null, 1);
   filearr := sys_dirlist (curdir, 1, null, 1);
   if (curdir <> '\\' and aref (curdir, length (curdir) - 1) <> ascii ('/'))
     curdir := concat (curdir, '/');
   if (start_from <> '/' and aref (start_from, length (start_from) - 1) <> ascii ('/'))
     start_from := concat (start_from, '/');
   http ('<?xml version="1.0" ?>', ret_xml);
   http (sprintf ('<PATH dir_name="%V">', start_from), ret_xml);
   if (aref (root, length (root) - 1) <> ascii ('/'))
     root := concat (root, '/');
   if (aref (curdir, length (curdir) - 1) <> ascii ('/'))
     curdir := concat (curdir, '/');
   len := length (dirarr);
   ix := 0;
   http ('<DIRS>', ret_xml);
   while (ix < len)
     {
       declare fst varchar;
       dirname := aref (dirarr, ix);
       fst := file_stat (concat (curdir, dirname));
       if (isstring (fst))
         modt := stringdate (fst);
       else
         modt := now();
       if (dirname <> '.')
	 http (sprintf ('<SUBDIR modify="%s" name="%s" />\n',
	       soap_print_box (modt, '', 2), dirname), ret_xml);
       ix := ix + 1;
     }
   http ('</DIRS><FILES>', ret_xml);
   len := length (filearr);
   ix := 0;
   while (ix < len)
     {
       dirname := aref (filearr, ix);
       modt := stringdate (file_stat (concat (curdir, dirname)));
       rflen := 0;
       rflen := file_stat (concat (curdir, dirname), 1);
       flen := atoi (rflen);
       mult := 0;
       if (lower (dirname) = 'folder.xsl')
	_sheet := concat (curdir, dirname);
       while ((flen / 1000) > 1)
	 {
	   mult := mult + 1;
	   flen := flen / 1000;
	 }
       http (sprintf ('<FILE modify="%s" rs="%s" hs="%d %s" name="%s" />\n',
	     soap_print_box (modt, '', 2), rflen, flen, aref (fsize, mult), dirname), ret_xml);
       ix := ix + 1;
     }
     http ('</FILES></PATH>', ret_xml);

     return string_output_string (ret_xml);
}
;


xslt_sheet ('http://local.virt/dir_output', xml_tree_doc ('
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
    <xsl:output method="text" />

    <xsl:template match="PATH">
	<xsl:variable name="path"><xsl:value-of select="@dir_name"/></xsl:variable>
	&lt;!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN"&gt;
	&lt;HTML&gt;
	&lt;TITLE&gt;Directory listing of <xsl:value-of select="$path"/>&lt;/TITLE&gt;
	&lt;BODY bgcolor="#FFFFFF" fgcolor="#000000"&gt;
	&lt;H4&gt;Index of <xsl:value-of select="$path"/>&lt;/H4&gt;
	  &lt;TABLE&gt;
	    &lt;tr&gt;&lt;td colspan=2 align="center"&gt;Name&lt;/td&gt;
	    &lt;td align="center"&gt;Last modified&lt;/td&gt;&lt;td align="center"&gt;Size&lt;/td&gt;&lt;/tr&gt;
	    &lt;tr&gt;&lt;td colspan=5&gt;&lt;HR /&gt;&lt;/td&gt;&lt;/tr&gt;

	<xsl:apply-templates select="DIRS">
	  <xsl:with-param name="f_path" select="$path"/>
	</xsl:apply-templates>

	<xsl:apply-templates select="FILES">
	  <xsl:with-param name="f_path" select="$path"/>
	</xsl:apply-templates>

	     &lt;tr&gt;&lt;td colspan=5&gt;&lt;HR /&gt;&lt;/td&gt;&lt;/tr&gt;
	  &lt;/TABLE&gt;
	&lt;/BODY&gt;
	&lt;/HTML&gt;
    </xsl:template>

    <xsl:template match="SUBDIR">
	 <xsl:param name="f_path" />
    	&lt;tr&gt;
	   &lt;td&gt;&lt;img src="/images/dir.gif"&gt;&lt;/td&gt;
	   &lt;td&gt;&lt;a href="<xsl:value-of select="$f_path"/><xsl:value-of select="@name"/>/"&gt;<xsl:value-of select="@name"/>&lt;/a&gt;&lt;/td&gt;
	   &lt;td&gt;<xsl:value-of select="@modify"/>&lt;/td&gt;&lt;td align="right"&gt;-&lt;/td&gt;
	&lt;/tr&gt;
    </xsl:template>

    <xsl:template match="FILE">
	 <xsl:param name="f_path" />
    	&lt;tr&gt;
	   &lt;td&gt;&lt;img src="/images/generic.gif"&gt;&lt;/td&gt;
	   &lt;td&gt;&lt;a href="<xsl:value-of select="$f_path"/><xsl:value-of select="@name"/>"&gt;<xsl:value-of select="@name"/>&lt;/a&gt;&lt;/td&gt;
	   &lt;td&gt;<xsl:value-of select="@modify"/>&lt;/td&gt;&lt;td align="right"&gt;<xsl:value-of select="@hs"/>&lt;/td&gt;
	&lt;/tr&gt;
    </xsl:template>

</xsl:stylesheet>'))
;


create procedure WS.WS.DIR_INDEX_XML (in path any, in params any, in lines any)
{
  declare _html, _xml, _sheet varchar;
  declare _b_opt any;

  _b_opt := NULL;

  if (exists (select 1 from HTTP_PATH
	where HP_LPATH = http_map_get ('domain') and HP_PPATH = http_map_get ('mounted')))
     select deserialize(HP_OPTIONS) into _b_opt from HTTP_PATH
	where HP_LPATH = http_map_get ('domain') and HP_PPATH = http_map_get ('mounted');

  _sheet := '';
  _xml := xml_tree_doc (WS.WS.DIR_INDEX_MAKE_XML (_sheet));

  if (_b_opt is not NULL)
    _b_opt := get_keyword ('browse_sheet', _b_opt, '');

  if (_sheet <> '')
    {
       xslt_sheet ('http://local.virt/custom_dir_output', xml_tree_doc (file_to_string (_sheet)));
       _html := cast (xslt ('http://local.virt/custom_dir_output', _xml) as varchar);
    }
  else if (_b_opt <> '')
    {
       _b_opt := concat (http_root(), '/', _b_opt);
       xslt_sheet ('http://local.virt/custom_dir_output', xml_tree_doc (file_to_string (_b_opt)));
       _html := cast (xslt ('http://local.virt/custom_dir_output', _xml) as varchar);
    }
  else
    _html := cast (xslt ('http://local.virt/dir_output', _xml) as varchar);

  return http (_html);
}
;

create procedure FTI_MAKE_SEARCH_STRING_INNER (in exp varchar, inout words any)
{
  declare exp1 varchar;
  declare war, vt any;
  declare m, n int;

  words := vector ();

  if (length (exp) < 2)
    return null;

  exp := trim (exp, ' ');

  if (strchr (exp, ' ') is null)
    {
      words := vector (trim (exp, '"'));
      return concat ('"', trim (exp, '"'), '"');
    }


  exp1 := '';

  if (strchr (exp, '"') is not null or
      strchr (exp, '''') is not null)
   {
     declare tmp, w varchar;
     tmp := exp;
     w := regexp_match ('["][^"]+["]|[''][^'']+['']|[^"'' ]+', tmp, 1);
     while (w is not null)
       {
         w := trim (w, '"'' ');
         if (upper(w) not in ('AND', 'NOT', 'NEAR', 'OR')
	     and length (w) > 1
             and not vt_is_noise (w, 'utf-8', 'x-any'))
           {
             exp1 := concat (exp1, sprintf ('"%s" AND ', w));
             words := vector_concat (words, vector (w));
           }
         w := regexp_match ('["][^"]+["]|[''][^'']+['']|[^"'' ]+', tmp, 1);
       }
     if (length (exp1) > 6)
       {
         exp1 := substring (exp1, 1, length (exp1) - 5);
         goto end_parse;
       }
   }

 vt := vt_batch (100, 'x-any', 'UTF-8');
 vt_batch_feed (vt, exp, 0, 0);

 war := vt_batch_strings_array (vt);
 words := vector ();

 m := length (war);
 n := 0;
 exp1 := '(';
 while (n < m)
   {
     declare word1 varchar;
     if (war[n] not in ('AND', 'NOT', 'NEAR', 'OR')
	 and length (war[n]) > 1
	 and not vt_is_noise (war[n], 'utf-8', 'x-any'))
       {
         word1 := war[n];
         words := vector_concat (words, vector (word1));
         if (strchr (word1, '.') is not null
	     or regexp_match ('[A-Za-z_][A-Za-z0-9_-]*', word1) is null)
           word1 := concat ('"', word1, '"');
         exp1 := concat (exp1, word1, ' AND ');
       }
     n := n + 2;
   }

 if (length (exp1) > 5)
   {
     exp1 := substring (exp1, 1, length (exp1) - 5);
     exp1 := concat (exp1, ')');
   }
 else
   exp1 := null;

end_parse:
  return exp1;
}
;

create procedure FTI_MAKE_SEARCH_STRING (in exp varchar)
{
  declare words any;
  return FTI_MAKE_SEARCH_STRING_INNER (exp, words);
}
;

create table DB.DBA.CLR_VAC (
        VAC_DATA LONG VARCHAR,
        VAC_INTERNAL_NAME VARCHAR,
        VAC_REAL_NAME VARCHAR,
        VAC_FULL_NAME VARCHAR,
        VAC_FULL_FILE_NAME VARCHAR,
        VAC_PERM_SET INTEGER,
        VAC_CREATE TIMESTAMP,
        primary key (VAC_INTERNAL_NAME)
)
;


create procedure exec_quiet (in expn varchar)
{
  declare sta, msg varchar;
  exec (expn, sta, msg);
}
;

-- drop type XMLType;

--!AWK PUBLIC
create type XMLType
as (
    xt_ent any,
    xt_schema varchar,
    xt_validated integer
   )
  method existsNode (_xpath varchar) returns integer,
  method existsNode (_xpath varchar, _nsmap varchar) returns integer,
  method extract (_xpath varchar) returns any,
  method extract (_xpath varchar, _nsmap varchar) returns any,
  method query (_xquery varchar) returns any,
  method isFragment () returns integer,
  method getClobVal () returns nvarchar,
  method getNumVal () returns numeric,
  method getStringVal () returns nvarchar,
  method transform (_xsl any) returns XMLType,
  method transform (_xsl any, _param_map any) returns XMLType,
  method isSchemaBased () returns integer,
  method getSchemaURL () returns varchar,
  method getRootElement () returns any,
  method createSchemaBasedXML () returns any,
  method createSchemaBasedXML (_url varchar) returns any,
  method createNonSchemaBasedXML () returns any,
  method getNamespace () returns nvarchar,
  method schemaValidate () returns any,
  method isSchemaValidated () returns integer,
  method setSchemaValidated () returns integer,
  method setSchemaValidated (_flag integer) returns integer,
  method isSchemaValid () returns integer,
  method isSchemaValid (_url varchar) returns integer,
  method isSchemaValid (_url varchar, _elemname varchar) returns integer,
  constructor method XMLType (_src any),
  constructor method XMLType (_src any, _schema varchar),
  constructor method XMLType (_src any, _schema varchar, _validated integer),
  constructor method XMLType (_src any, _schema varchar, _validated integer, _wellformed integer)
;

call exec_quiet ('alter type XMLType add method transform (_xsl any) returns XMLType')
;

call exec_quiet ('alter type XMLType add method transform (_xsl any, _param_map any) returns XMLType')
;

call exec_quiet ('alter type XMLType drop method getStringVal () returns varchar')
;

call exec_quiet ('alter type XMLType drop method getNamespace () returns any')
;

call exec_quiet ('alter type XMLType add method query (_xquery varchar) returns any')
;

call exec_quiet ('alter type XMLType add method getStringVal () returns nvarchar')
;

call exec_quiet ('alter type XMLType add method getNamespace () returns nvarchar')
;

call exec_quiet ('alter type XMLType add method setSchemaValidated () returns integer')
;

call exec_quiet ('alter type XMLType add method setSchemaValidated (_flag integer) returns integer')
;

create method existsNode (in _xpath varchar) returns integer for XMLType
{
  declare _hit any;
  _hit := xpath_eval (_xpath, self.xt_ent, 1);
  if (__tag (_hit) = 230)
    return 1;
  return 0;
}
;

create method existsNode (in _xpath varchar, in _nsmap varchar) returns integer for XMLType
{
  declare _hit any;
  if (_nsmap is not null)
    if (_xpath <> '' and aref (_xpath, 0) = '[')
      _xpath := concat ('[', _nsmap, ' ', subseq (_xpath, 1));
    else
      _xpath := concat ('[', _nsmap, ']', _xpath);
  _hit := xpath_eval (_xpath, self.xt_ent, 1);
  if (__tag (_hit) = 230)
    return 1;
  return 0;
}
;

create method extract (in _xpath varchar) returns any for XMLType
{
  declare _hit any;
  _hit := xpath_eval (_xpath, self.xt_ent, 1);
  if (__tag (_hit) = 230)
    return XMLType (_hit);
  return _hit;
}
;

create method query (in _xquery varchar) returns any for XMLType
{
  declare _hit any;
  _hit := xquery_eval (_xquery, self.xt_ent, 1);
  if (__tag (_hit) = 230)
    return XMLType (_hit);
  return _hit;
}
;

create method extract (in _xpath varchar, in _nsmap varchar) returns any for XMLType
{
  declare _hit any;
  if (_nsmap is not null)
    if (_xpath <> '' and aref (_xpath, 0) = '[')
      _xpath := concat ('[', _nsmap, ' ', subseq (_xpath, 1));
    else
      _xpath := concat ('[', _nsmap, ']', _xpath);
  _hit := xpath_eval (_xpath, self.xt_ent, 1);
  if (__tag(_hit) = 230)
    return XMLType (_hit);
  return _hit;
}
;

create method isFragment () returns integer for XMLType
{
  if (xpath_eval ('count(/*)', self.xt_ent) = 1)
    return 0;
  return 1;
}
;

create method getClobVal () returns nvarchar for XMLType
{
  return xpath_eval ('serialize(.)', self.xt_ent, 1);
}
;

create method getNumVal () returns numeric for XMLType
{
  return xpath_eval ('number(.)', self.xt_ent, 1);
}
;

create method getStringVal () returns nvarchar for XMLType
{
  return xpath_eval ('string(.)', self.xt_ent, 1);
}
;

create method transform (inout _xsl any) returns XMLType for XMLType
{
  signal ('42000', 'Virtuoso does not support method XMLType.transform(); use xslt built-in function instead');
}
;

create method transform (inout _xsl any, in _param_map any) returns XMLType for XMLType
{
  signal ('42000', 'Virtuoso does not support method XMLType.transform(); use xslt built-in function instead');
}
;

create method isSchemaBased () returns integer for XMLType
{
  if (self.xt_schema is null)
    return 0;
  return 1;
}
;

create method getSchemaURL () returns varchar for XMLType
{
  return self.xt_schema;
}
;

create method getRootElement () returns any for XMLType
{
  declare _roots any;
  _roots := xpath_eval ('/*', self.xt_ent, 0);
  if (length (_roots) <> 1)
    return null;
  return XMLType (aref (_roots, 0), self.xt_schema);
}
;

create method createSchemaBasedXML () returns any for XMLType
{
  return XMLType (self.xt_ent);
}
;

create method createSchemaBasedXML (in _url varchar) returns any for XMLType
{
  if (_url = self.xt_schema)
    return self;
  return XMLType (self.xt_ent, _url);
}
;

create method createNonSchemaBasedXML () returns any for XMLType
{
  return XMLType (self.xt_ent);
}
;

create method getNamespace () returns nvarchar for XMLType
{
  declare _res nvarchar;
  if (self.xt_schema is null)
    return null;
  if (xpath_eval ('count(/*)', self.xt_ent) <> 1)
    return null;
  _res := xpath_eval ('namespace-uri(/*)', self.xt_ent);
-- The following two lines are not correct: namespace of a local name is an empty string, not NULL.
--  if (length (_res) = 0)
--    return null;
  return _res;
}
;

create method schemaValidate () returns any for XMLType
{
  if (self.xt_validated <> 0)
    return null;
  if (self.xt_schema is null)
    signal ('42000', 'Document is not schema-based');
  xml_validate_schema (self.xt_ent,
	0,
	coalesce (xml_doc_get_base_uri (self.xt_ent), ''),
	'UTF-8',
	'x-any',
        'Validation=SGML FsaBadWs=IGNORE SignalOnError=ENABLE',
	'xs:', ':xs', self.xt_schema );
  self.xt_validated := 1;
}
;

create method isSchemaValidated () returns integer for XMLType
{
  return self.xt_validated;
}
;

create method setSchemaValidated () returns integer for XMLType
{
  if (self.xt_schema is null)
    signal ('42000', 'Document is not schema-based');
  self.xt_validated := 1;
  return 1;
}
;

create method setSchemaValidated (in _flag integer) returns integer for XMLType
{
  if (self.xt_schema is null)
    signal ('42000', 'Document is not schema-based');
  self.xt_validated := _flag;
  return _flag;
}
;

create method isSchemaValid () returns integer for XMLType
{
  if (self.xt_schema is null)
    signal ('42000', 'Document is not schema-based and no schema URL is provided for XMLType.isSchemaValid().');
  whenever sqlstate '42000' goto err;
  xml_validate_schema (self.xt_ent,
	0,
	coalesce (xml_doc_get_base_uri (self.xt_ent), ''),
	'UTF-8',
	'x-any',
        'Validation=SGML FsaBadWs=IGNORE SignalOnError=ENABLE',
	'xs:', ':xs', self.xt_schema );
  return 1;

err:
  return 0;
}
;

create method isSchemaValid (in _url varchar) returns integer for XMLType
{
  whenever sqlstate '42000' goto err;
  xml_validate_schema (self.xt_ent,
	0,
	coalesce (xml_doc_get_base_uri (self.xt_ent), ''),
	'UTF-8',
	'x-any',
        'Validation=SGML FsaBadWs=IGNORE SignalOnError=ENABLE',
	'xs:', ':xs', _url );
  return 1;

err:
  return 0;
}
;

create method isSchemaValid (in _url varchar, in _elemname varchar) returns integer for XMLType
{
  whenever sqlstate '42000' goto err;
  xml_validate_schema (self.xt_ent,
	0,
	coalesce (xml_doc_get_base_uri (self.xt_ent), ''),
	'UTF-8',
	'x-any',
        'Validation=SGML FsaBadWs=IGNORE SignalOnError=ENABLE',
	'xs:', ':xs', _url );
  return 1;

err:
  return 0;
}
;

create constructor method XMLType (in _src any) for XMLType
{
  if (__tag (_src) = 230)
    self.xt_ent := _src;
  else if (__tag (_src) = 193)
    self.xt_ent := xml_tree_doc(_src);
  else
    self.xt_ent := xtree_doc (_src);
  self.xt_schema := null;
  self.xt_validated := 0;
}
;

create constructor method XMLType (in _src any, in _schema varchar) for XMLType
{
  if (__tag (_src) = 230)
    self.xt_ent := _src;
  else if (__tag (_src) = 193)
    self.xt_ent := xml_tree_doc(_src);
  else
    self.xt_ent := xtree_doc (_src);
  self.xt_schema := _schema;
  self.xt_validated := 0;
}
;

create constructor method XMLType (in _src any, in _schema varchar, in _validated integer) for XMLType
{
  if (__tag (_src) = 230)
    self.xt_ent := _src;
  else if (__tag (_src) = 193)
    self.xt_ent := xml_tree_doc(_src);
  else
    self.xt_ent := xtree_doc (_src);
  self.xt_schema := _schema;
  self.xt_validated := _validated;
}
;

create constructor method XMLType (in _src any, in _schema varchar, in _validated integer, in _wellformed integer) for XMLType
{
  if (__tag (_src) = 230)
    self.xt_ent := _src;
  else if (__tag (_src) = 193)
    self.xt_ent := xml_tree_doc(_src);
  else
    self.xt_ent := xtree_doc (_src);
  self.xt_schema := _schema;
  self.xt_validated := _validated;
}
;

create constructor method XMLType (in _src any, in _schema varchar := null, in _validated integer := 0, in _wellformed integer := 0) for XMLType
{
  if (__tag (_src) = 230)
    self.xt_ent := _src;
  else
    self.xt_ent := xtree_doc (_src);
  self.xt_schema := _schema;
  self.xt_validated := _validated;
}
;

create function createXML (in _src any, in _schema varchar := null, in _validated integer := 0, in _wellformed integer := 0) returns XMLType
{
  declare _res XMLType;
  _res := XMLType (_src, _schema, _validated, _wellformed);
  return _res;
}
;

grant execute on XMLType to public
;

--!AWK PUBLIC
create procedure DB.DBA.SYS_CREATE_XML_SCHEMA (in _txt varchar)
{
  declare _log varchar;
  declare _parsed any;
  declare _xsd_top any;
  declare _target_ns any;
  declare _cres_uri any;
  _parsed := xtree_doc (_txt, 0, '(argument of CREATE XML SCHEMA statement)', 'UTF-8', 'x-any', 'Validation=RIGOROUS BuildStandalone=ENABLE');
  _xsd_top := xpath_eval ('[xmlns:xs="http://www.w3.org/2001/XMLSchema"] /xs:schema', _parsed, 0);
  if (0 = length(_xsd_top))
    signal ('XSD01', 'No XMLSchema top element found in the provided XML document');
  if (1 < length(_xsd_top))
    signal ('XSD01', 'The provided XML document is not a valida schema');
  _target_ns := xpath_eval ('@targetNamespace', _xsd_top[0]);
  if (_target_ns is NULL)
    signal ('XSD01', 'No "targetNamespace" attribute in top-level "xs:schema" element in the provided XML document');
  if (_target_ns = '')
    signal ('XSD01', 'The value of the "targetNamespace" attribute in top-level "xs:schema" element is not a well-formed URI');
  _cres_uri := 'x-virt-cache-xsd--' || _target_ns;
  if (exists (select top 1 1 from SYS_CACHED_RESOURCES where CRES_URI=_cres_uri))
    signal ('XSD01', sprintf ('The XMLSchema for target namespace "%s" is already declared', _target_ns));
  insert into SYS_CACHED_RESOURCES (CRES_URI, CRES_CONTENT)
  values (_cres_uri, _txt);
}
;

--!AWK PUBLIC
create procedure DB.DBA.XML_COLUMN_SCHEMA_VALIDATE (
  in _table varchar, in _column varchar, in _xml any,
  in _xsd_uri varchar, in _top_name varchar, in _dtd_cfg varchar)
{
  declare _log varchar;
--  dbg_obj_print ('\nValidating', _table, _column, _xml, _xsd_uri, _top_name, _dtd_cfg);
  if (_xml is null)
    return null;
--  _log :=
  xml_validate_schema (
    _xml, 0, sprintf('(value to be placed in column %s of %s)', _table, _column),
    'UTF-8', 'x-any',
    case when (_dtd_cfg is null) then 'Validation=RIGOROUS AttrMisformat=ERROR AttrMissing=ERROR FSA=ERROR IdDuplicates=ERROR IdrefIntegrity=ERROR SignalOnError=ENABLE' else concat (_dtd_cfg, ' SignalOnError=ENABLE') end,
    'xs:', ':xs', 'x-virt-cache-xsd--' || _xsd_uri );
--  dbg_obj_print ('\nValidation log:', _log);
--  signal ('OBLOM', sprintf( '{%d-%s}', __tag(_log), cast (_log as varchar)));
  return null;
}
;

--!AWK PUBLIC
create function SYS_TREE_OF_ARRAYS_CONTAINS (in _haystack any, in _needle any)
{
  declare _ctr integer;
  if (__tag (_haystack) = __tag (_needle))
    return equ (_haystack, _needle);
  if (isstring (_haystack) or not (isarray (_haystack)))
    return 0;
  _ctr := length (_haystack);
  while (_ctr > 0)
    {
      _ctr := _ctr - 1;
      if (SYS_TREE_OF_ARRAYS_CONTAINS (aref (_haystack, _ctr), _needle))
        return 1;
    }
  return 0;
}
;

--!AWK PUBLIC
create procedure DB.DBA.SYS_DROP_XML_SCHEMA (in _target_ns varchar)
{
  declare _log varchar;
  declare _parsed any;
  declare _xsd_top any;
  declare _cres_uri any;
  _cres_uri := 'x-virt-cache-xsd--' || _target_ns;
  if (not exists (select top 1 1 from SYS_CACHED_RESOURCES where CRES_URI=_cres_uri))
    signal ('XSD01', sprintf ('Undefined XMLSchema name in DROP XML SCHEMA "%s"', _target_ns));
  for
    select C_TABLE from SYS_CONSTRAINTS where
      SYS_TREE_OF_ARRAYS_CONTAINS (deserialize(C_MODE), cast (_target_ns as varchar)) do
    signal ('XSD01', sprintf ('Can not DROP XML SCHEMA "%s" because the schema is in use in constraint of table %s', _target_ns, C_TABLE));
  delete from SYS_CACHED_RESOURCES where CRES_URI =_cres_uri;
}
;

--!AWK PLBIF regexp_like
create procedure REGEXP_LIKE (in source_string any, in pattern any, in match_parameter integer := null)
returns integer
{
  if (match_parameter is not null)
    signal ('22023', 'match_parameter not supported yet', 'SR371');
  if (source_string is null or pattern is null)
    return 0;
  else
    {
      if ((not isstring (source_string)) and (not iswidestring (source_string)))
	source_string := cast (source_string as varchar);
      if ((not isstring (pattern)) and (not iswidestring (pattern)))
	pattern := cast (pattern as varchar);
    }
  return either (isnull (regexp_match (pattern, source_string)), 0, 1);
}
;


--!AWK PLBIF regexp_replace
create procedure REGEXP_REPLACE (in source_string any, in pattern any,
            in replace_string varchar := '', in position integer := 1,
	    in occurrence any := 1, in match_parameter integer := null)
{
  if (source_string is null or pattern is null or replace_string is null)
    return source_string;
  else
    {
      if ((not isstring (source_string)) and (not iswidestring (source_string)))
	source_string := cast (source_string as varchar);
      if ((not isstring (pattern)) and (not iswidestring (pattern)))
	pattern := cast (pattern as varchar);
      if ((not isstring (replace_string)) and (not iswidestring (replace_string)))
	replace_string := cast (replace_string as varchar);
    }

  if (match_parameter is not null)
    signal ('22023', 'match_parameter not supported yet', 'SR372');
  declare cur_pos, copied_up_to, nth integer;
  declare ret any;

  ret := either (iswidestring (source_string), N'', '');
  cur_pos := position - 1;
  copied_up_to := position - 1;
  nth := 1;

  while (cur_pos < length (source_string))
    {
      declare exprs any;

      exprs := regexp_parse (pattern, source_string, cur_pos);

      if (not isarray (exprs))
	goto done;

      declare start_inx, end_inx integer;
      start_inx := exprs[0];
      end_inx := exprs[1];

      if (occurrence is null or occurrence = nth)
	{
	  if (start_inx > copied_up_to)
	    ret := concat (ret, subseq (source_string, copied_up_to, start_inx));

	  if (length (exprs) > 2)
	    {
	      declare expr_inx integer;
	      declare replace_str any;
	      declare replace_string_tmp any;
	      replace_string_tmp := replace_string;
	      expr_inx := 1;

	      while (expr_inx * 2 < length (exprs))
		{
		  declare replace_str_found varchar;

		  if (exprs[expr_inx * 2] >= 0 and exprs[expr_inx * 2 + 1] >= 0)
		    replace_str_found := subseq (source_string, exprs[expr_inx * 2], exprs [expr_inx * 2 + 1]);
		  else
		    replace_str_found := either (iswidestring (source_string), N'', '');

		  replace_str := sprintf ('\\%d', expr_inx);
		  if (iswidestring (source_string))
		    replace_str := cast (replace_str as nvarchar);
		  replace_string_tmp := replace (replace_string_tmp, replace_str,
		       replace_str_found);
		  expr_inx := expr_inx + 1;
		}
	      while (expr_inx < 10)
		{
		  replace_str := sprintf ('\\%d', expr_inx);
		  if (iswidestring (source_string))
		    replace_str := cast (replace_str as nvarchar);
		  replace_string_tmp := replace (replace_string_tmp, replace_str,
		    either (iswidestring (source_string), N'', ''));
		  expr_inx := expr_inx + 1;
		}
	      ret := concat (ret, replace_string_tmp);
	    }
	  else
	    ret := concat (ret, replace_string);
	  copied_up_to := end_inx;
	  if (occurrence is not null)
	    goto done;
	}

      nth := nth + 1;
      cur_pos := end_inx;
    }
done:
  if (copied_up_to < length (source_string))
    ret := concat (ret, subseq (source_string, copied_up_to, length (source_string)));

  return ret;
}
;


--!AWK PLBIF regexp_instr
create procedure REGEXP_INSTR (in source_string varchar, in pattern varchar,
 in start_position integer := 1, in occurrence integer := 1, in return_option integer := 0,
 in match_parameter integer := null)
returns integer
{

  if (source_string is null or pattern is null)
    return null;
  else
    {
      if ((not isstring (source_string)) and (not iswidestring (source_string)))
	source_string := cast (source_string as varchar);
      if ((not isstring (pattern)) and (not iswidestring (pattern)))
	pattern := cast (pattern as varchar);
    }

  if (match_parameter is not null)
    signal ('22023', 'match_parameter not supported yet', 'SR373');

  declare cur_pos, nth integer;

  cur_pos := start_position - 1;
  nth := 1;

  while (cur_pos < length (source_string) and nth <= occurrence)
    {
      declare exprs any;

      exprs := regexp_parse (pattern, source_string, cur_pos);

      if (not isarray (exprs))
	return null;

      declare start_inx, end_inx integer;
      start_inx := exprs[0];
      end_inx := exprs[1];

      if (occurrence = nth)
	{
	  if (return_option = 0)
	    return start_inx + 1;
	  else if (return_option = 1)
	    return end_inx + 1;
	  else
	    signal ('22023', 'return_option should be 0 or 1', 'SR374');
	}

      cur_pos := end_inx;
      nth := nth + 1;
    }

  return null;
}
;

--!AWK PLBIF http_requested_url
create procedure HTTP_REQUESTED_URL ()
{
  declare hf, pat, proto, meth, so, eo, lines any;
  if (not is_http_ctx())
    signal ('22023', 'http_requested_url function outside of http context', 'HT069');
  lines := http_request_header ();
  pat := lines[0];
  proto := http_request_get ('SERVER_PROTOCOL');
  meth := http_request_get ('REQUEST_METHOD');
  so := strstr (pat, meth || ' ');
  eo := strstr (pat, ' ' || proto);
  pat := trim(subseq (pat, so + length (meth) + 1, eo), ' \r\n');
  hf := WS.WS.PARSE_URI (pat);
  return WS.WS.EXPAND_URL(soap_current_url (), hf[2]);
}
;

--!AWK PLBIF http_url_handler
create procedure HTTP_URL_HANDLER ()
{
  if (not is_http_ctx())
    signal ('22023', 'http_url_handler function outside of http context', 'HT068');
  return WS.WS.EXPAND_URL(soap_current_url (), http_path());
}
;

create procedure DB.DBA.SERVICES_WSIL (in path any, in params any, in lines any)
{
  declare host, intf, requrl, proto, rhost varchar;
  declare arr any;
  host := http_map_get ('vhost');
  intf := http_map_get ('lhost');
  requrl := http_requested_url ();
  arr := WS.WS.PARSE_URI (requrl);
  proto := arr[0];
  rhost := arr[1];

  if (host = server_http_port () and intf = server_http_port ())
    {
      host := '*ini*';
      intf := '*ini*';
    }

  http_header ('Content-Type: text/xml\r\n');
  http('<?xml version="1.0" ?>');
  http('<inspection xmlns="http://schemas.xmlsoap.org/ws/2001/10/inspection">');
  for select HP_LPATH, deserialize (HP_SOAP_OPTIONS) as opts from DB.DBA.HTTP_PATH where HP_HOST = host and HP_LISTEN_HOST = intf and HP_PPATH = '/SOAP/' do
    {
      declare nam any;
      nam := trim (HP_LPATH, '/ ');
      if (isarray (opts))
	nam := get_keyword ('ServiceName', opts, nam);
      http ('<service>');
      http (sprintf ('<name>%V</name>', nam));
      http (sprintf ('<description referencedNamespace="http://schemas.xmlsoap.org/wsdl/" location="%s://%s%s/services.wsdl"/>', proto, rhost, HP_LPATH));
      http ('</service>');
    }
  http('</inspection>');
}
;

-- /* scheduler */

create procedure DB.DBA.SCHEDULER_NOTIFY ()
{
  declare arr, err_text, current_rec, mime_parts, hdrs, hostname any;

  arr := vector ();

  current_rec := null;
  err_text := '';
  hostname := sys_stat ('st_host_name');

  if (not isstring (hostname))
    return;

  hdrs := sprintf ('Subject: [Scheduled Event Errors] %s\r\n', hostname);

  for select SE_NAME, SE_SQL, SE_LAST_ERROR, SE_NOTIFY from SYS_SCHEDULED_EVENT where
    SE_LAST_ERROR is not null and SE_ENABLE_NOTIFY = 1 and SE_NOTIFICATION_SENT = 0 order by SE_NOTIFY do
    {
      arr := vector_concat (arr, vector (vector (SE_NAME, SE_SQL, SE_LAST_ERROR, SE_NOTIFY)));
    }

  commit work;
  foreach (any elm in arr) do
    {
      declare _SE_NAME, _SE_SQL, _SE_LAST_ERROR, _SE_NOTIFY any;
      _SE_NAME := elm[0];
      _SE_SQL := elm[1];
      _SE_LAST_ERROR := elm[2];
      _SE_NOTIFY := elm[3];


      if (current_rec is null)
	{
	  current_rec := _SE_NOTIFY;
	  err_text := '';
	}
      else if (current_rec <> _SE_NOTIFY)
	{
	  mime_parts := vector (DB.DBA.MIME_PART ('text/html', null, null, err_text));
          update SYS_SCHEDULED_EVENT set SE_NOTIFICATION_SENT = 1 where SE_NOTIFY = current_rec and SE_NOTIFICATION_SENT = 0;
	  commit work;
	  {
	    declare exit handler for sqlstate '*'
	    {
	      rollback work;
	      goto next;
	    };
	    smtp_send (null, current_rec, current_rec, concat (hdrs, DB.DBA.MIME_BODY (mime_parts)));
	    next:;
	  }
	  current_rec := _SE_NOTIFY;
	  err_text := '';
        }
      err_text := err_text || '<pre>' || _SE_NAME || ' ' || _SE_SQL || '\r\n' || blob_to_string (_SE_LAST_ERROR) || '</pre>\r\n' ;
    }
  if (length (err_text) and current_rec is not null)
    {
      mime_parts := vector (DB.DBA.MIME_PART ('text/html', null, null, err_text));
      update SYS_SCHEDULED_EVENT set SE_NOTIFICATION_SENT = 1 where SE_NOTIFY = current_rec and SE_NOTIFICATION_SENT = 0;
      commit work;
      smtp_send (null, current_rec, current_rec, concat (hdrs, DB.DBA.MIME_BODY (mime_parts)));
    }
}
;


create procedure
SYS_CHECK_OLD_BLOG ()
{
  if (registry_get ('__weblog2_tables_is_upgrated') = 'OK')
    return;
  if(exists(select 1 from DB.DBA.SYS_KEYS where KEY_TABLE = 'DB.DBA.SYS_BLOGS'))
    {
       declare mtd, dta, state, msg any;
       state := '00000';
       exec ('select count (*) from DB.DBA.SYS_BLOGS', state, msg, vector (), 1, mtd, dta);
       if ('00000' <> state)
	 return;
       if (dta[0][0] > 1)
         log_message ('Detected old blog instance. Please update it with latest blog.vad');
    }
}
;


SYS_CHECK_OLD_BLOG ()
;

--!AWK PUBLIC
create procedure
HTTP_GET_HOST ()
{
  declare ret varchar;
  if (is_http_ctx ())
    {
      ret := http_request_header (http_request_header (), 'Host', null, sys_connected_server_address ());
      if (isstring (ret) and strchr (ret, ':') is null)
        {
          declare hp varchar;
          declare hpa any;
          hp := sys_connected_server_address ();
          hpa := split_and_decode (hp, 0, '\0\0:');
          ret := ret || ':' || hpa[1];
        }
    }
  else
   {
     ret := sys_connected_server_address ();
     if (ret is null)
       ret := sys_stat ('st_host_name')||':'||server_http_port ();
   }

  return ret;
}
;

--!AWK PUBLIC
create procedure
date_rfc1123 (in dt datetime)
{
  return soap_print_box (dt, '', 1);
}
;

--!AWK PUBLIC
create procedure
date_iso8601 (in dt datetime)
{
  return soap_print_box (dt, '', 0);
}
;

create procedure DB.DBA.INSTALLER_VAD (in _pak_name varchar)
{
  declare state, msg, m_dta, res any;
  declare out_message varchar;
  declare idx, len integer;

  state := '00000';
  msg := 'none';
  out_message := '';

  exec ('VAD_INSTALL(?, 0, 1)',
    state, msg, vector (_pak_name), 100, m_dta, res);

  if ('00000' <> state)
    {
	out_message := msg;
	goto finish;
    }

  idx := 0;
  len := length (res);

  while (idx < len)
    {
	if (res[idx][0] <> '00000')
	  out_message := out_message || res[idx][1] || ' ';
	idx := idx + 1;
    }

finish:;

  string_to_file ('../vad/install.res', out_message, -2);
  return;
}
;

create procedure DB.DBA.VACUUM (in table_name varchar := '%', in index_name varchar := '%')
{
  declare stmt, stat, msg varchar;
  set isolation='uncommitted';
  for select distinct KEY_TABLE as _table_name, KEY_NAME as _index_name from SYS_KEYS where
    KEY_TABLE like table_name and KEY_NAME like index_name and KEY_MIGRATE_TO is null do
    {
      if (not exists (select 1 from SYS_VIEWS where V_NAME = _table_name) and
	  not exists (select 1 from SYS_REMOTE_TABLE where RT_NAME = _table_name))
         {
	   stmt := sprintf ('select count(*) from "%I"."%I"."%I" table option (index %I, vacuum 0)',
	     	 name_part (_table_name,0),
	     	 name_part (_table_name,1),
	     	 name_part (_table_name,2),
	     	 name_part (_index_name,2)
	     	 );
	   stat := '00000';
	   exec (stmt, stat, msg, vector (), 0);
	   dbg_printf ('%s %s', stat, stmt);
         }
    }
}
;
