IMPORT os
IMPORT util
IMPORT security

PUBLIC TYPE t_user_id VARCHAR(20)
PUBLIC TYPE t_user_auth VARCHAR(200)
PUBLIC TYPE t_user_name VARCHAR(100)
PUBLIC TYPE t_user_status INTEGER
PUBLIC TYPE t_table_name VARCHAR(50)
PUBLIC TYPE t_where_part VARCHAR(250)

PUBLIC TYPE t_user_disp RECORD
           user_id t_user_id,
           user_has_pswd BOOLEAN,
           user_name t_user_name,
           user_status t_user_status
       END RECORD

PUBLIC TYPE t_datafilter RECORD
           f_user_id t_user_id,
           table_name t_table_name,
           last_mtime DATETIME YEAR TO FRACTION(3),
           temp_mtime DATETIME YEAR TO FRACTION(3),
           where_part t_where_part
       END RECORD

PUBLIC CONSTANT v_undef VARCHAR(10) = "<undef>"
PUBLIC CONSTANT v_undef_text VARCHAR(20) = "<Undefined>"

PUBLIC CONSTANT base_datetime = DATETIME(1900-01-01 00:00:00.000) YEAR TO FRACTION(3)

PRIVATE DEFINE dbsynclog DYNAMIC ARRAY OF RECORD
                  log_when DATETIME YEAR TO FRACTION(3),
                  log_object STRING,
                  log_comment STRING
               END RECORD

PRIVATE DEFINE bfn_list DYNAMIC ARRAY OF RECORD
                  name STRING
               END RECORD

-- Check UTF-8 and char length semantics: Works only on server.
FUNCTION check_utf8() RETURNS (INTEGER,STRING)
    IF ORD("€") == 8364 AND length("€") == 1 THEN
       RETURN 0, NULL
    ELSE
       RETURN -1, "Application locale must be UTF-8, with char length semantics"
    END IF
END FUNCTION

-- Connection

FUNCTION get_dbc_args() RETURNS (STRING,STRING,STRING,STRING,STRING)
    DEFINE i INTEGER
    DEFINE dbname, dbsrce, dbdriv, uname, upswd STRING
    FOR i = 1 TO num_args()
        CASE arg_val(i)
        WHEN "-d" LET i = i + 1 LET dbname = arg_val(i)
        WHEN "-f" LET i = i + 1 LET dbsrce = arg_val(i)
        WHEN "-o" LET i = i + 1 LET dbdriv = arg_val(i)
        WHEN "-u" LET i = i + 1 LET uname = arg_val(i)
        WHEN "-w" LET i = i + 1 LET upswd = arg_val(i)
        END CASE
    END FOR
    RETURN dbname, dbsrce, dbdriv, uname, upswd
END FUNCTION

FUNCTION do_connect(
    dbname STRING,
    dbsrce STRING,
    dbdriv STRING,
    uname STRING,
    upswd STRING
) RETURNS INTEGER
    DEFINE tmp, dbspec STRING
    LET dbspec = dbname
    IF length(dbdriv)>0 THEN
       LET tmp = tmp,IIF(tmp IS NULL,"+",",")
       LET tmp = tmp,SFMT("driver='%1'",dbdriv)
    END IF
    IF length(dbsrce)>0 THEN
       LET tmp = tmp,IIF(tmp IS NULL,"+",",")
       LET tmp = tmp,SFMT("source='%1'",dbsrce)
    END IF
    IF tmp IS NOT NULL THEN
       LET dbspec = dbname || tmp
    END IF
    WHENEVER ERROR CONTINUE
    IF length(uname) == 0 THEN
       CONNECT TO dbspec
    ELSE
       CONNECT TO dbspec USER uname USING upswd
    END IF
    WHENEVER ERROR STOP
    RETURN sqlca.sqlcode
END FUNCTION

-- Users

FUNCTION users_disp_load(
    arr DYNAMIC ARRAY OF t_user_disp
) RETURNS ()
    DEFINE i INTEGER,
           rec RECORD
               user_id t_user_id,
               user_auth t_user_auth,
               user_name t_user_name,
               user_status t_user_status
           END RECORD
    CALL arr.clear()
    DECLARE c_users CURSOR FOR
      SELECT user_id, user_auth, user_name, user_status
       FROM users
       WHERE user_id != v_undef
       ORDER BY user_id
    LET i=0
    FOREACH c_users INTO rec.*
        LET i=i+1
        LET arr[i].user_id = rec.user_id
        LET arr[i].user_has_pswd = (length(rec.user_auth)>0)
        LET arr[i].user_name = rec.user_name
        LET arr[i].user_status = rec.user_status
    END FOREACH
    FREE c_users
END FUNCTION

FUNCTION users_server_table() RETURNS ()
    WHENEVER ERROR CONTINUE
    DROP TABLE users
    WHENEVER ERROR STOP
    CREATE TABLE users (
       user_id VARCHAR(20) NOT NULL,
       user_auth VARCHAR(200),
       user_name VARCHAR(100) NOT NULL,
       user_status INTEGER NOT NULL,
       PRIMARY KEY(user_id)
    )
END FUNCTION

FUNCTION user_id_exists(usrid t_user_id) RETURNS BOOLEAN
    DEFINE id t_user_id
    SELECT user_id INTO id FROM users
                     WHERE user_id = usrid
    RETURN ( sqlca.sqlcode == 0 )
END FUNCTION

FUNCTION users_add(
    usrid t_user_id,
    uauth t_user_auth,
    uname t_user_name,
    ustat t_user_status
) RETURNS ()
    INSERT INTO users VALUES (usrid, uauth, uname, ustat)
END FUNCTION

PUBLIC FUNCTION pswd_match(p1 STRING, p2 STRING) RETURNS BOOLEAN
    IF length(p1)==0 AND length(p2)==0 THEN -- No password at all
       RETURN TRUE
    END IF
    -- Values must match, if one is NULL=>FALSE,
    -- both NULL case tested before with LENGTH()==0
    IF p1==p2 THEN
       RETURN TRUE
    ELSE
       RETURN FALSE
    END IF
END FUNCTION

FUNCTION users_mod(
    usrid t_user_id,
    uname t_user_name,
    ustat t_user_status
) RETURNS ()
    UPDATE users SET
           user_name = uname,
           user_status = ustat
       WHERE user_id=usrid
END FUNCTION

FUNCTION users_clear_auth(usrid t_user_id) RETURNS ()
    UPDATE users SET
           user_auth = NULL
       WHERE user_id=usrid
END FUNCTION

FUNCTION users_del(usrid t_user_id) RETURNS ()
    DELETE FROM datafilter WHERE user_id = usrid
    DELETE FROM users WHERE user_id = usrid
END FUNCTION

FUNCTION users_reset_mtimes(usrid t_user_id) RETURNS ()
    DEFINE mtime DATETIME YEAR TO FRACTION(3)
    LET mtime = base_datetime
    UPDATE datafilter
       SET last_mtime = mtime,
           temp_mtime = NULL
     WHERE user_id = usrid
END FUNCTION

FUNCTION users_check(
    usrid t_user_id,
    uauth t_user_auth -- Encrypted
) RETURNS STRING
    DEFINE uname t_user_name,
           curr_auth t_user_auth, -- Encrypted
           ustat t_user_status
    SELECT user_name, user_auth, user_status
      INTO uname, curr_auth, ustat
      FROM users
      WHERE user_id = usrid
    CASE
        WHEN sqlca.sqlcode == NOTFOUND
          RETURN "user_invalid"
        WHEN NOT pswd_match(uauth, curr_auth)
          RETURN "user_invpswd"
        WHEN ustat == -1
          RETURN "user_denied"
        OTHERWISE
          RETURN "success"
    END CASE
END FUNCTION

-- uauth is in clear text
PUBLIC FUNCTION user_auth_encrypt(uauth STRING) RETURNS STRING
    DEFINE result STRING,
           dgst security.Digest
    IF length(uauth)==0 THEN
       RETURN NULL
    END IF
    TRY
        LET dgst = security.Digest.CreateDigest("SHA256")
        CALL dgst.AddStringData(uauth)
        LET result = dgst.DoBase64Digest()
    CATCH
        DISPLAY "ERROR : ", status, " - ", sqlca.sqlerrm
        EXIT PROGRAM(-1)
    END TRY
    RETURN result
END FUNCTION

FUNCTION users_change_auth(
    usrid t_user_id,
    old t_user_auth, -- Encrypted
    new t_user_auth  -- Encrypted
) RETURNS STRING
    DEFINE tmp t_user_auth  -- Encrupted
    SELECT user_auth INTO tmp FROM users WHERE user_id=usrid
    IF sqlca.sqlcode==NOTFOUND THEN
       RETURN "user_invalid"
    END IF
    IF NOT pswd_match(tmp, old) THEN
       RETURN "user_invpswd"
    END IF
    TRY
       UPDATE users SET user_auth = new WHERE user_id=usrid
    CATCH
       RETURN "user_upderr"
    END TRY
    RETURN "success"
END FUNCTION

-- Sequences

FUNCTION sequence_create(
  tabname STRING,
  startnum INTEGER
) RETURNS INTEGER
  WHENEVER ERROR CONTINUE
  EXECUTE IMMEDIATE "CREATE SEQUENCE "||tabname||"_seq START "||startnum
  WHENEVER ERROR STOP
  RETURN sqlca.sqlcode
END FUNCTION

FUNCTION sequence_drop(tabname STRING) RETURNS INTEGER
  WHENEVER ERROR CONTINUE
  EXECUTE IMMEDIATE "DROP SEQUENCE "||tabname||"_seq"
  WHENEVER ERROR STOP
  RETURN sqlca.sqlcode
END FUNCTION

FUNCTION sequence_next(tabname STRING) RETURNS BIGINT
  DEFINE sqlstmt STRING
  DEFINE newseq BIGINT
  CASE fgl_db_driver_type()
    WHEN "pgs"
      LET sqlstmt = SFMT("SELECT nextval('%1_seq')",tabname)||unique_row_condition()
    WHEN "sqt" -- Assuming primary key column is integer and named <tabname>_num!
      LET sqlstmt = SFMT("SELECT MAX(%1_num) + 1 FROM %1",tabname)
    OTHERWISE
      LET sqlstmt = SFMT("SELECT %1_seq.nextval ",tabname)||unique_row_condition()
  END CASE
  WHENEVER ERROR CONTINUE
  PREPARE seq_next FROM sqlstmt
  IF sqlca.sqlcode!=0 THEN RETURN -1 END IF
  EXECUTE seq_next INTO newseq
  IF sqlca.sqlcode!=0 THEN RETURN -1 END IF
  WHENEVER ERROR STOP
  RETURN newseq
END FUNCTION

FUNCTION unique_row_condition() RETURNS STRING
    CASE fgl_db_driver_type()
        WHEN "ifx" RETURN " FROM systables WHERE tabid=1"
        WHEN "db2" RETURN " FROM sysibm.systables WHERE name='SYSTABLES'"
        WHEN "pgs" RETURN " FROM pg_class WHERE relname='pg_class'"
        WHEN "ora" RETURN " FROM dual"
        OTHERWISE RETURN " "
    END CASE
END FUNCTION

FUNCTION sequence_mobile_new(
    tabname STRING,
    colname STRING
) RETURNS INTEGER
    DEFINE newseq INTEGER
    TRY
       PREPARE seq_mob_new FROM "SELECT MIN("||colname||")-1 FROM "||tabname
               ||" WHERE "||colname||" < 0"
       EXECUTE seq_mob_new INTO newseq
       IF newseq IS NULL OR sqlca.sqlcode == NOTFOUND THEN
          LET newseq = -1
       END IF
    CATCH
       DISPLAY "Could not get sequence for table: ", tabname
       DISPLAY SQLERRMESSAGE
       EXIT PROGRAM 1
    END TRY
    RETURN newseq
END FUNCTION

-- Data filters

FUNCTION datafilter_table() RETURNS ()
    WHENEVER ERROR CONTINUE
    DROP TABLE datafilter
    WHENEVER ERROR STOP
    CREATE TABLE datafilter (
        user_id VARCHAR(20) NOT NULL,
        table_name VARCHAR(50) NOT NULL,
        last_mtime DATETIME YEAR TO FRACTION(3) NOT NULL,
        temp_mtime DATETIME YEAR TO FRACTION(3),
        where_part VARCHAR(250),
        PRIMARY KEY(user_id, table_name),
        FOREIGN KEY (user_id) REFERENCES users (user_id)
    )
END FUNCTION

FUNCTION datafilter_load(
    uid t_user_id,
    arr DYNAMIC ARRAY OF t_datafilter
) RETURNS ()
    DEFINE i INTEGER
    CALL arr.clear()
    DECLARE c_tabinfo CURSOR FOR
      SELECT f.user_id,
             f.table_name,
             f.last_mtime,
             f.temp_mtime,
             f.where_part
          FROM datafilter f
         WHERE user_id = uid
         ORDER BY table_name
    LET i=1
    FOREACH c_tabinfo INTO arr[i].*
        LET i=i+1
    END FOREACH
    CALL arr.deleteElement(arr.getLength())
    FREE c_tabinfo
END FUNCTION

FUNCTION datafilter_define(
    uid t_user_id,
    tn t_table_name,
    wp t_where_part
) RETURNS ()
    DEFINE mtime DATETIME YEAR TO FRACTION(3)
    LET mtime = base_datetime
    INSERT INTO datafilter VALUES ( uid, tn, mtime, NULL, wp )
END FUNCTION

FUNCTION datafilter_remove(
    uid t_user_id,
    tn t_table_name
) RETURNS ()
    DELETE FROM datafilter
     WHERE user_id = uid AND table_name = tn
END FUNCTION

FUNCTION datafilter_set_where_part(
    uid t_user_id,
    tn t_table_name,
    wp t_where_part
) RETURNS ()
    DEFINE mtime DATETIME YEAR TO FRACTION(3)
    LET mtime = base_datetime
    UPDATE datafilter SET
       where_part = wp,
       last_mtime = mtime, -- force first sync
       temp_mtime = NULL
     WHERE user_id = uid AND table_name = tn
END FUNCTION

FUNCTION datafilter_get_last_mtime(
    uid t_user_id,
    tn t_table_name,
    first_sync BOOLEAN
) RETURNS DATETIME YEAR TO FRACTION(3)
    DEFINE last_user_mtime DATETIME YEAR TO FRACTION(3)
    IF first_sync THEN
       LET last_user_mtime = base_datetime
    ELSE
       SELECT last_mtime INTO last_user_mtime
         FROM datafilter
        WHERE user_id = uid AND table_name = tn
       IF sqlca.sqlcode==NOTFOUND THEN
          LET last_user_mtime = base_datetime
       END IF
    END IF
    RETURN last_user_mtime
END FUNCTION

FUNCTION datafilter_get_filter(
    uid t_user_id,
    tn t_table_name
) RETURNS t_where_part
    DEFINE wp t_where_part
    SELECT where_part INTO wp
      FROM datafilter
     WHERE user_id = uid AND table_name = tn
    IF sqlca.sqlcode==NOTFOUND OR length(wp)=0 THEN
       LET wp = NULL
    END IF
    RETURN wp
END FUNCTION

FUNCTION datafilter_register_mtime(
    uid t_user_id,
    tn t_table_name,
    mtime DATETIME YEAR TO FRACTION(3)
) RETURNS INTEGER
    UPDATE datafilter
       SET temp_mtime = mtime
     WHERE user_id = uid AND table_name = tn
    RETURN IIF(sqlca.sqlerrd[3]==1,0,-1)
END FUNCTION

FUNCTION datafilter_commit_mtime(
    uid t_user_id,
    tn t_table_name
) RETURNS INTEGER
    DEFINE mtime DATETIME YEAR TO FRACTION(3)
    SELECT temp_mtime INTO mtime
      FROM datafilter
     WHERE user_id = uid AND table_name = tn
       AND temp_mtime IS NOT NULL
    IF sqlca.sqlcode==NOTFOUND THEN
       RETURN -2
    END IF
    UPDATE datafilter
       SET last_mtime = mtime,
           temp_mtime = NULL
     WHERE user_id = uid AND table_name = tn
    RETURN IIF(sqlca.sqlerrd[3]==1,0,-1)
END FUNCTION


-- DB Sync log

FUNCTION dbsynclog_clear() RETURNS ()
    CALL dbsynclog.clear()
END FUNCTION

FUNCTION dbsynclog_record(
    failure VARCHAR(50),
    tabname VARCHAR(50),
    ident VARCHAR(50),
    comment VARCHAR(200)
) RETURNS ()
    CONSTANT fs='{"failure":"%1", "table":"%2", "ident":"%3"}'
    DEFINE x INTEGER
    LET x = dbsynclog.getLength() + 1
    LET dbsynclog[x].log_when = CURRENT
    LET dbsynclog[x].log_object = SFMT(fs,failure,tabname,ident)
    LET dbsynclog[x].log_comment = comment
END FUNCTION

FUNCTION dbsynclog_count() RETURNS INTEGER
    RETURN dbsynclog.getLength()
END FUNCTION

FUNCTION dbsynclog_show() RETURNS ()
    DEFINE arr DYNAMIC ARRAY OF RECORD
               num INTEGER,
               object VARCHAR(100),
               comment VARCHAR(200)
           END RECORD,
           det RECORD
               failure STRING,
               table STRING,
               ident INTEGER
           END RECORD,
           x INTEGER
    IF dbsynclog.getLength()==0 THEN
       ERROR %"contacts.error.emptylog"
       RETURN
    END IF
    FOR x=1 TO dbsynclog.getLength()
        CALL util.JSON.parse(dbsynclog[x].log_object, det)
        LET arr[x].num = x
        LET arr[x].object = det.failure||": ",
                            det.ident USING "<<<<<<<<<<<<<<<<"
        LET arr[x].comment = dbsynclog[x].log_comment
    END FOR
    OPEN WINDOW w_synclog WITH FORM "list1" ATTRIBUTES(TEXT=%"logform.title")
    DISPLAY ARRAY arr TO sr.*
        ATTRIBUTES(UNBUFFERED, ACCEPT=FALSE)
        ON ACTION clear ATTRIBUTES(TEXT=%"logform.action.clear")
           CALL DIALOG.deleteAllRows("sr")
           CALL dbsynclog.clear()
           MESSAGE %"contacts.mess.synclogclr"
    END DISPLAY
    CLOSE WINDOW w_synclog
END FUNCTION

-- Debug

FUNCTION my_startlog(fn STRING) RETURNS ()
    CALL startlog( os.Path.join(os.Path.pwd(),fn) )
END FUNCTION

FUNCTION my_errorlog(txt STRING) RETURNS ()
    CALL errorlog(txt)
END FUNCTION

-- Files

FUNCTION create_empty_file(fn STRING) RETURNS ()
    DEFINE c base.Channel
    LET c = base.Channel.create()
    CALL c.openFile(fn, "w")
    CALL c.close()
END FUNCTION

-- Data

FUNCTION intarr_to_list(
   arr DYNAMIC ARRAY OF INTEGER
) RETURNS STRING
   DEFINE i INTEGER, res STRING
   FOR i=1 TO arr.getLength()
       IF i=1 THEN
          LET res = arr[i]
       ELSE
          LET res = res,",",arr[i]
       END IF
   END FOR
   RETURN res
END FUNCTION

FUNCTION intarr_lookup(
    arr DYNAMIC ARRAY OF INTEGER,
    val INTEGER
) RETURNS INTEGER
    DEFINE i INTEGER
    FOR i=1 TO arr.getLength()
        IF arr[i] == val THEN RETURN i END IF
    END FOR
    RETURN 0
END FUNCTION

-- Dialogs

FUNCTION mbox_ync(title STRING, msg STRING) RETURNS SMALLINT
    DEFINE res SMALLINT
    MENU title ATTRIBUTES(STYLE="dialog",COMMENT=msg)
        ON ACTION yes     LET res = 1
        ON ACTION no      LET res = 0
        ON ACTION cancel  LET res = -1
    END MENU
    RETURN res
END FUNCTION

FUNCTION mbox_yn(title STRING, msg STRING) RETURNS BOOLEAN
    DEFINE res BOOLEAN
    MENU title ATTRIBUTES(STYLE="dialog",COMMENT=msg)
        ON ACTION yes LET res = TRUE
        ON ACTION no  LET res = FALSE
    END MENU
    RETURN res
END FUNCTION

FUNCTION mbox_ok(title,msg) RETURNS ()
    DEFINE title, msg STRING
    MENU title ATTRIBUTES(STYLE="dialog",COMMENT=msg)
        ON ACTION accept
        --ON ACTION ok
    END MENU
END FUNCTION

-- BYTE file names

FUNCTION bfn_get(
    fs STRING,
    id STRING,
    ts DATETIME YEAR TO FRACTION(3)
) RETURNS STRING
    DEFINE fn, s STRING,
           x INTEGER
    IF ts IS NULL THEN
       LET s = "new"
    ELSE
       LET s = (util.Datetime.toSecondsSinceEpoch(ts) * 1000) USING "<<<<<<<<<<<<<<<<<<<<<<<"
    END IF
    LET fn = SFMT(fs, id, s)
    FOR x=1 TO bfn_list.getLength()
        IF bfn_list[x].name == fn THEN EXIT FOR END IF
    END FOR
    IF x > bfn_list.getLength() THEN
       LET bfn_list[x].name = fn
    END IF
    RETURN fn
END FUNCTION

FUNCTION bfn_cleanup() RETURNS ()
    DEFINE x,s INTEGER
    FOR x=1 TO bfn_list.getLength()
        LET s = os.Path.delete( bfn_list[x].name )
    END FOR
END FUNCTION
