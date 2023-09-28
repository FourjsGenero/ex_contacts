IMPORT FGL libutil

FUNCTION enter_password() RETURNS (INTEGER,STRING,STRING)
    DEFINE rec RECORD
                   old_pwd STRING,
                   new_pwd STRING,
                   new_pwd_conf STRING
               END RECORD

    OPEN WINDOW w_password WITH FORM "password"

    INPUT BY NAME rec.* ATTRIBUTES(UNBUFFERED)

        ON CHANGE new_pwd
           LET rec.new_pwd_conf = NULL

        AFTER INPUT
           IF NOT int_flag THEN
              IF libutil.pswd_match(rec.new_pwd, rec.new_pwd_conf) THEN
                  EXIT INPUT
              ELSE
                  ERROR %"password.unmatch"
                  NEXT FIELD new_pwd_conf
              END IF
           END IF

    END INPUT

    CLOSE WINDOW w_password

    IF int_flag THEN
       LET int_flag = FALSE
       RETURN -1, NULL, NULL
    ELSE
       RETURN 0, rec.old_pwd, rec.new_pwd
    END IF

END FUNCTION
