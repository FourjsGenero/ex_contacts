IMPORT os
IMPORT util
IMPORT security

PUBLIC TYPE t_user_id VARCHAR(20)
PUBLIC TYPE t_user_auth VARCHAR(200)
PUBLIC TYPE t_user_name VARCHAR(100)
PUBLIC TYPE t_table_name VARCHAR(50)
PUBLIC TYPE t_where_part VARCHAR(250)

PUBLIC TYPE t_user_disp RECORD
           user_id VARCHAR(50),
           user_has_pswd BOOLEAN,
           user_name VARCHAR(100),
           user_status INTEGER
       END RECORD

PUBLIC TYPE t_datafilter RECORD
           f_user_id VARCHAR(50),
           table_name VARCHAR(100),
           last_mtime DATETIME YEAR TO FRACTION(3),
           temp_mtime DATETIME YEAR TO FRACTION(3),
           where_part VARCHAR(250)
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

FUNCTION mobile_type()
    IF base.Application.isMobile() THEN
       RETURN ui.Interface.getFrontEndName()
    ELSE
       RETURN "SERVER"
    END IF
END FUNCTION

-- Check UTF-8 and char length semantics: Works only on server.
FUNCTION check_utf8()
    IF ORD("€") == 8364 AND LENGTH("€") == 1 THEN
       RETURN 0, NULL
    ELSE
       RETURN -1, "Application locale must be UTF-8, with char length semantics"
    END IF
{
    DEFINE ch base.Channel, data STRING
    LET ch = base.Channel.create()
    CALL ch.openPipe("fglrun -i mbcs 2>&1", "r")
    LET data = ch.readLine()
    IF data NOT MATCHES "*UTF-8*" THEN
       RETURN -1, "Application locale must be UTF-8"
    END IF
    LET data = fgl_getenv("FGL_LENGTH_SEMANTICS")
    IF data IS NULL OR data != "CHAR" THEN
       RETURN -2, "Application length semantics must be CHAR"
    END IF
    RETURN 0, NULL
}
END FUNCTION

-- Connection

FUNCTION get_dbc_args()
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

FUNCTION do_connect(dbname,dbsrce,dbdriv,uname,upswd)
    DEFINE dbname,dbsrce,dbdriv,uname,upswd STRING
    DEFINE tmp, dbspec STRING
    LET dbspec = dbname
    IF LENGTH(dbdriv)>0 THEN
       LET tmp = tmp,IIF(tmp IS NULL,"+",",")
       LET tmp = tmp,SFMT("driver='%1'",dbdriv)
    END IF
    IF LENGTH(dbsrce)>0 THEN
       LET tmp = tmp,IIF(tmp IS NULL,"+",",")
       LET tmp = tmp,SFMT("source='%1'",dbsrce)
    END IF
    IF tmp IS NOT NULL THEN
       LET dbspec = dbname || tmp
    END IF
    WHENEVER ERROR CONTINUE
    IF LENGTH(uname) == 0 THEN
       CONNECT TO dbspec
    ELSE
       CONNECT TO dbspec USER uname USING upswd
    END IF
    WHENEVER ERROR STOP
    RETURN SQLCA.SQLCODE
END FUNCTION

-- Users

FUNCTION users_disp_load(arr)
    DEFINE arr DYNAMIC ARRAY OF t_user_disp
    DEFINE i INTEGER,
           rec RECORD
               user_id VARCHAR(50),
               user_auth BOOLEAN,
               user_name VARCHAR(100),
               user_status INTEGER
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
        LET arr[i].user_has_pswd = (LENGTH(rec.user_auth)>0)
        LET arr[i].user_name = rec.user_name
        LET arr[i].user_status = rec.user_status
    END FOREACH
    FREE c_users
END FUNCTION

FUNCTION users_server_table()
    WHENEVER ERROR CONTINUE
    DROP TABLE users
    WHENEVER ERROR STOP
    CREATE TABLE users (
       user_id VARCHAR(20) NOT NULL,
       user_auth VARCHAR(200),
       user_name VARCHAR(100) NOT NULL,
       user_status SMALLINT NOT NULL,
       PRIMARY KEY(user_id)
    )
END FUNCTION

FUNCTION users_add(usrid,uauth,uname)
    DEFINE usrid t_user_id,
           uauth t_user_auth,
           uname t_user_name
    INSERT INTO users VALUES (usrid, uauth, uname, 1)
END FUNCTION

PUBLIC FUNCTION pswd_match(p1,p2)
    DEFINE p1 STRING, p2 STRING
    IF LENGTH(p1)==0 AND LENGTH(p2)==0 THEN -- No password at all
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

FUNCTION users_mod(usrid,uname,ustat)
    DEFINE usrid t_user_id,
           uname t_user_name,
           ustat SMALLINT
    UPDATE users SET
           user_name = uname,
           user_status = ustat
       WHERE user_id=usrid
END FUNCTION

FUNCTION users_clear_auth(usrid)
    DEFINE usrid t_user_id
    UPDATE users SET
           user_auth = NULL
       WHERE user_id=usrid
END FUNCTION

FUNCTION users_suspend(usrid)
    DEFINE usrid t_user_id
    UPDATE users SET user_status = 1 WHERE user_id=usrid
END FUNCTION

FUNCTION users_del(usrid)
    DEFINE usrid t_user_id
    DELETE FROM datafilter WHERE user_id = usrid
    DELETE FROM users WHERE user_id = usrid
END FUNCTION

FUNCTION users_reset_mtimes(usrid)
    DEFINE usrid t_user_id
    DEFINE mtime DATETIME YEAR TO FRACTION(3)
    LET mtime = base_datetime
    UPDATE datafilter
       SET last_mtime = mtime,
           temp_mtime = NULL
     WHERE user_id = usrid
END FUNCTION

FUNCTION users_check(usrid,uauth)
    DEFINE usrid t_user_id,
           uauth t_user_auth -- Encrypted
    DEFINE uname t_user_name,
           curr_auth t_user_auth, -- Encrypted
           ustat INTEGER
    SELECT user_name, user_auth, user_status
      INTO uname, curr_auth, ustat
      FROM users
      WHERE user_id = usrid
    CASE
        WHEN SQLCA.SQLCODE == NOTFOUND
          RETURN "user_invalid"
        WHEN NOT pswd_match(uauth, curr_auth)
          RETURN "user_invpswd"
        WHEN ustat == -1
          RETURN "user_denied"
        OTHERWISE
          RETURN "success"
    END CASE
END FUNCTION

PUBLIC FUNCTION user_auth_encrypt(uauth)
    DEFINE uauth STRING -- Clear
    DEFINE result STRING,
           dgst security.Digest
    IF LENGTH(uauth)==0 THEN
       RETURN NULL
    END IF
    TRY
        LET dgst = security.Digest.CreateDigest("SHA256")
        CALL dgst.AddStringData(uauth)
        LET result = dgst.DoBase64Digest()
    CATCH
        DISPLAY "ERROR : ", STATUS, " - ", SQLCA.SQLERRM
        EXIT PROGRAM(-1)
    END TRY
    RETURN result
END FUNCTION

FUNCTION users_change_auth(usrid,old,new)
    DEFINE usrid t_user_id,
           old t_user_auth, -- Encrypted
           new t_user_auth  -- Encrypted
    DEFINE tmp t_user_auth  -- Encrupted
    SELECT user_auth INTO tmp FROM users WHERE user_id=usrid
    IF SQLCA.SQLCODE==NOTFOUND THEN
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

FUNCTION sequence_create(tabname,startnum)
  DEFINE tabname STRING, startnum INTEGER
  WHENEVER ERROR CONTINUE
  EXECUTE IMMEDIATE "CREATE SEQUENCE "||tabname||"_seq START "||startnum
  WHENEVER ERROR STOP
  RETURN SQLCA.SQLCODE
END FUNCTION

FUNCTION sequence_drop(tabname)
  DEFINE tabname STRING
  WHENEVER ERROR CONTINUE
  EXECUTE IMMEDIATE "DROP SEQUENCE "||tabname||"_seq"
  WHENEVER ERROR STOP
  RETURN SQLCA.SQLCODE
END FUNCTION

FUNCTION sequence_next(tabname)
  DEFINE tabname STRING
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
  IF SQLCA.SQLCODE!=0 THEN RETURN -1 END IF
  EXECUTE seq_next INTO newseq
  IF SQLCA.SQLCODE!=0 THEN RETURN -1 END IF
  WHENEVER ERROR STOP
  RETURN newseq
END FUNCTION

FUNCTION unique_row_condition()
    CASE fgl_db_driver_type()
        WHEN "ifx" RETURN " FROM systables WHERE tabid=1"
        WHEN "db2" RETURN " FROM sysibm.systables WHERE name='SYSTABLES'"
        WHEN "pgs" RETURN " FROM pg_class WHERE relname='pg_class'"
        WHEN "ora" RETURN " FROM dual"
        OTHERWISE RETURN " "
    END CASE
END FUNCTION

FUNCTION sequence_mobile_new(tabname,colname)
    DEFINE tabname, colname STRING
    DEFINE newseq INTEGER
    TRY
       PREPARE seq_mob_new FROM "SELECT MIN("||colname||")-1 FROM "||tabname
               ||" WHERE "||colname||" < 0"
       EXECUTE seq_mob_new INTO newseq
       IF newseq IS NULL OR SQLCA.SQLCODE == NOTFOUND THEN
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

FUNCTION datafilter_table()
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

FUNCTION datafilter_load(uid, arr)
    DEFINE uid VARCHAR(50),
           arr DYNAMIC ARRAY OF t_datafilter
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


FUNCTION datafilter_define(uid, tn, wp)
    DEFINE uid t_user_id,
           tn t_table_name,
           wp t_where_part
    DEFINE mtime DATETIME YEAR TO FRACTION(3)
    LET mtime = base_datetime
    INSERT INTO datafilter VALUES ( uid, tn, mtime, NULL, wp )
END FUNCTION

FUNCTION datafilter_remove(uid, tn)
    DEFINE uid t_user_id,
           tn t_table_name
    DELETE FROM datafilter
     WHERE user_id = uid AND table_name = tn
END FUNCTION

FUNCTION datafilter_set_where_part(uid, tn, wp)
    DEFINE uid t_user_id,
           tn t_table_name,
           wp t_where_part
    DEFINE mtime DATETIME YEAR TO FRACTION(3)
    LET mtime = base_datetime
    UPDATE datafilter SET
       where_part = wp,
       last_mtime = mtime, -- force first sync
       temp_mtime = NULL
     WHERE user_id = uid AND table_name = tn
END FUNCTION

FUNCTION datafilter_get_last_mtime(uid, tn, first_sync)
    DEFINE uid t_user_id,
           tn t_table_name,
           first_sync BOOLEAN
    DEFINE last_user_mtime DATETIME YEAR TO FRACTION(3)
    IF first_sync THEN
       LET last_user_mtime = base_datetime
    ELSE
       SELECT last_mtime INTO last_user_mtime
         FROM datafilter
        WHERE user_id = uid AND table_name = tn
       IF SQLCA.SQLCODE==NOTFOUND THEN
          LET last_user_mtime = base_datetime
       END IF
    END IF
    RETURN last_user_mtime
END FUNCTION

FUNCTION datafilter_get_filter(uid, tn)
    DEFINE uid t_user_id, tn t_table_name
    DEFINE wp VARCHAR(250)
    SELECT where_part INTO wp
      FROM datafilter
     WHERE user_id = uid AND table_name = tn
    IF SQLCA.SQLCODE==NOTFOUND OR LENGTH(wp)=0 THEN
       LET wp = NULL
    END IF
    RETURN wp
END FUNCTION

FUNCTION datafilter_register_mtime(uid, tn, mtime)
    DEFINE uid t_user_id,
           tn t_table_name,
           mtime DATETIME YEAR TO FRACTION(3)
    UPDATE datafilter
       SET temp_mtime = mtime
     WHERE user_id = uid AND table_name = tn
    RETURN IIF(SQLCA.SQLERRD[3]==1,0,-1)
END FUNCTION

FUNCTION datafilter_commit_mtime(uid, tn)
    DEFINE uid t_user_id,
           tn t_table_name
    DEFINE mtime DATETIME YEAR TO FRACTION(3)
    SELECT temp_mtime INTO mtime
      FROM datafilter
     WHERE user_id = uid AND table_name = tn
       AND temp_mtime IS NOT NULL
    IF SQLCA.SQLCODE==NOTFOUND THEN
       RETURN -2
    END IF
    UPDATE datafilter
       SET last_mtime = mtime,
           temp_mtime = NULL
     WHERE user_id = uid AND table_name = tn
    RETURN IIF(SQLCA.SQLERRD[3]==1,0,-1)
END FUNCTION


-- DB Sync log

FUNCTION dbsynclog_clear()
    CALL dbsynclog.clear()
END FUNCTION

FUNCTION dbsynclog_record(failure,tabname,ident,comment)
    CONSTANT fs='{"failure":"%1", "table":"%2", "ident":"%3"}'
    DEFINE failure, tabname, ident VARCHAR(50), comment VARCHAR(200)
    DEFINE x INTEGER
    LET x = dbsynclog.getLength() + 1
    LET dbsynclog[x].log_when = CURRENT
    LET dbsynclog[x].log_object = SFMT(fs,failure,tabname,ident)
    LET dbsynclog[x].log_comment = comment
END FUNCTION

FUNCTION dbsynclog_count()
    RETURN dbsynclog.getLength()
END FUNCTION

FUNCTION dbsynclog_show()
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
        ON ACTION clear
            -- FIXME: To allow 2.50 compilation for server-side programs...
            --ATTRIBUTES(TEXT=%"logform.action.clear")
           CALL DIALOG.deleteAllRows("sr")
           CALL dbsynclog.clear()
           MESSAGE %"contacts.mess.synclogclr"
    END DISPLAY
    CLOSE WINDOW w_synclog
END FUNCTION

-- Debug

FUNCTION my_startlog(fn)
    DEFINE fn STRING
    CALL startlog( os.Path.join(os.Path.pwd(),fn) )
END FUNCTION

FUNCTION my_errorlog(txt)
    DEFINE txt STRING
    CALL errorlog(txt)
END FUNCTION

-- Files

FUNCTION create_empty_file(fn)
    DEFINE fn STRING, c base.Channel
    LET c = base.Channel.create()
    CALL c.openFile(fn, "w")
    CALL c.close()
END FUNCTION

-- Data

FUNCTION intarr_to_list(arr)
   DEFINE arr DYNAMIC ARRAY OF INTEGER
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

FUNCTION intarr_lookup(arr,val)
    DEFINE arr DYNAMIC ARRAY OF INTEGER,
           val INTEGER
    DEFINE i INTEGER
    FOR i=1 TO arr.getLength()
        IF arr[i] == val THEN RETURN i END IF
    END FOR
    RETURN 0
END FUNCTION

-- Dialogs

FUNCTION mbox_ync(title,msg)
    DEFINE title, msg STRING
    DEFINE res SMALLINT
    MENU title ATTRIBUTES(STYLE="dialog",COMMENT=msg)
        ON ACTION yes     LET res = 1
        ON ACTION no      LET res = 0
        ON ACTION cancel  LET res = -1
    END MENU
    RETURN res
END FUNCTION

FUNCTION mbox_yn(title,msg)
    DEFINE title, msg STRING
    DEFINE res BOOLEAN
    MENU title ATTRIBUTES(STYLE="dialog",COMMENT=msg)
        ON ACTION yes LET res = TRUE
        ON ACTION no  LET res = FALSE
    END MENU
    RETURN res
END FUNCTION

FUNCTION mbox_ok(title,msg)
    DEFINE title, msg STRING
    MENU title ATTRIBUTES(STYLE="dialog",COMMENT=msg)
        ON ACTION accept
        --ON ACTION ok
    END MENU
END FUNCTION

-- BYTE file names

FUNCTION bfn_get(fs, id, ts)
    DEFINE fs STRING,
           id STRING,
           ts DATETIME YEAR TO FRACTION(3)
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

FUNCTION bfn_cleanup()
    DEFINE x,s INTEGER
    FOR x=1 TO bfn_list.getLength()
        LET s = os.Path.delete( bfn_list[x].name )
    END FOR
END FUNCTION

