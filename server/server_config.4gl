IMPORT FGL libutil

DEFINE a_users DYNAMIC ARRAY OF libutil.t_user_disp
DEFINE r_user libutil.t_user_disp
DEFINE a_tabinfo DYNAMIC ARRAY OF libutil.t_datafilter
DEFINE wpinput VARCHAR(250)

MAIN
    DEFINE dbname, dbsrce, dbdriv, uname, upswd STRING,
           s,x INTEGER

    CALL libutil.get_dbc_args()
         RETURNING dbname, dbsrce, dbdriv, uname, upswd
    IF arg_val(1) == "-h" OR dbname IS NULL THEN
       DISPLAY "Usage: server_config options ..."
       DISPLAY "   -d dbname"
       DISPLAY "   -f dbsrce"
       DISPLAY "   -o driver"
       DISPLAY "   -u user"
       DISPLAY "   -w pswd"
       EXIT PROGRAM 1
    END IF

    LET s = do_connect(dbname, dbsrce, dbdriv, uname, upswd)
    IF s !=0 THEN
       DISPLAY "ERROR:", s, " ", SQLERRMESSAGE
       EXIT PROGRAM 1
    END IF

    OPEN FORM f1 FROM "users"
    DISPLAY FORM f1

    CALL libutil.users_disp_load(a_users)
    IF a_users.getLength()>1 THEN
       CALL libutil.datafilter_load(a_users[1].user_id, a_tabinfo)
    END IF

    DIALOG ATTRIBUTES(UNBUFFERED)

      -- User info
      DISPLAY ARRAY a_users TO users.*
        BEFORE ROW
           CALL libutil.datafilter_load(a_users[arr_curr()].user_id, a_tabinfo)
           IF a_tabinfo.getLength()>0 THEN
              CALL DIALOG.setCurrentRow("tabinfo",1)
              LET wpinput = a_tabinfo[1].where_part
           ELSE
              LET wpinput = NULL
           END IF
        ON UPDATE
           LET r_user.* = a_users[arr_curr()].*
           IF edit_user(FALSE) THEN
              LET a_users[arr_curr()].* = r_user.*
           END IF
        ON APPEND
           IF edit_user(TRUE) THEN
              LET a_users[arr_curr()].* = r_user.*
           END IF
        ON DELETE
           IF mbox_yn("Delete this user?") THEN
              LET int_flag = FALSE
              TRY
                 CALL libutil.users_del(a_users[arr_curr()].user_id)
              CATCH
                 CALL mbox_ok(SQLERRMESSAGE)
                 LET int_flag = TRUE
              END TRY
           ELSE
              LET int_flag = TRUE
           END IF
        ON ACTION rsttim
           IF mbox_yn("Reset user's sync timestamps?") THEN
              CALL libutil.users_reset_mtimes(a_users[arr_curr()].user_id)
              CALL libutil.datafilter_load(a_users[arr_curr()].user_id, a_tabinfo)
           END IF
        ON ACTION clpswd
           IF mbox_yn("Clear user's password?") THEN
              CALL libutil.users_clear_auth(a_users[arr_curr()].user_id)
              LET a_users[arr_curr()].user_has_pswd = FALSE
           END IF
        ON ACTION reload
           LET wpinput = NULL
           CALL libutil.users_disp_load(a_users)
           CALL a_tabinfo.clear()
           IF a_users.getLength() > 0 THEN
              LET x = DIALOG.getCurrentRow("users")
              IF x > a_users.getLength() THEN
                 LET x = a_users.getLength()
              END IF
              CALL DIALOG.setCurrentRow("users",x)
              CALL libutil.datafilter_load(a_users[x].user_id, a_tabinfo)
              IF a_tabinfo.getLength()>0 THEN
                 CALL DIALOG.setCurrentRow("tabinfo",1)
                 LET wpinput = a_tabinfo[1].where_part
              END IF
           END IF
      END DISPLAY

      -- Table info
      DISPLAY ARRAY a_tabinfo TO tabinfo.*
        BEFORE ROW
           LET wpinput = a_tabinfo[arr_curr()].where_part
      END DISPLAY

      INPUT BY NAME wpinput
        ON ACTION save
           LET x = DIALOG.getCurrentRow("tabinfo")
           IF x > 0 THEN
              IF NOT check_sql(a_tabinfo[x].table_name, wpinput) THEN
                 NEXT FIELD wpinput
              END IF
              LET a_tabinfo[x].where_part = wpinput
              CALL libutil.datafilter_set_where_part(
                   a_tabinfo[x].f_user_id,
                   a_tabinfo[x].table_name,
                   wpinput)
           END IF
      END INPUT

      ON ACTION close
         EXIT DIALOG

    END DIALOG

END MAIN

FUNCTION check_sql(tabname, where_part)
    DEFINE tabname, where_part STRING
    DEFINE sql STRING, cnt INTEGER
    IF length(where_part)==0 THEN RETURN TRUE END IF
    LET sql = SFMT("SELECT COUNT(*) FROM %1 WHERE %2", tabname, where_part)
    TRY
        PREPARE s_check FROM sql
        EXECUTE s_check INTO cnt
        CALL mbox_ok(SFMT("%1 rows matching this where part", cnt))
    CATCH
        CALL mbox_ok(SFMT("Invalid SQL where part:\n(SQLCODE=%1) %2",sqlca.sqlcode,SQLERRMESSAGE))
        RETURN FALSE
    END TRY
    RETURN TRUE
END FUNCTION

FUNCTION edit_user(new)
    DEFINE new BOOLEAN
    IF new THEN
       INITIALIZE r_user.* TO NULL
       LET r_user.user_has_pswd = FALSE
       LET r_user.user_status = 1
    END IF
    INPUT r_user.* FROM users[arr_curr()].*
          ATTRIBUTES( WITHOUT DEFAULTS )
        BEFORE INPUT
           CALL DIALOG.setFieldActive("user_id", new)
        AFTER FIELD user_id
           IF new THEN
              SELECT user_id FROM users
                     WHERE user_id = r_user.user_id
              IF sqlca.sqlcode == 0 THEN
                 ERROR "User id exists already"
                 NEXT FIELD user_id
              END IF
           END IF
    END INPUT
    IF int_flag THEN
       RETURN FALSE
    END IF
    TRY
       IF new THEN
          CALL libutil.users_add(
                       r_user.user_id,
                       NULL,
                       r_user.user_name
               )
          CALL libutil.datafilter_define(r_user.user_id, "city", NULL)
          CALL libutil.datafilter_define(r_user.user_id, "contact", NULL)
       ELSE
          CALL libutil.users_mod(
                       r_user.user_id,
                       r_user.user_name,
                       r_user.user_status
               )
       END IF
    CATCH
       CALL mbox_ok(SQLERRMESSAGE)
       RETURN FALSE
    END TRY
    RETURN TRUE
END FUNCTION

PRIVATE FUNCTION mbox_ok(msg)
    DEFINE msg STRING
    CALL libutil.mbox_ok("Contacts Server",msg)
END FUNCTION

PRIVATE FUNCTION mbox_yn(msg)
    DEFINE msg STRING
    RETURN libutil.mbox_yn("Contacts Server",msg)
END FUNCTION

