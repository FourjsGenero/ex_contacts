IMPORT FGL libutil
IMPORT FGL mkcontacts

MAIN
    DEFINE dbname, dbsrce, dbdriv, uname, upswd STRING,
           i, s INTEGER, sample BOOLEAN

    CALL libutil.get_dbc_args()
         RETURNING dbname, dbsrce, dbdriv, uname, upswd
    FOR i = 1 TO num_args()
        CASE arg_val(i)
        WHEN "-s" LET i = i + 1 LET sample = TRUE
        END CASE
    END FOR
    IF arg_val(1) == "-h" OR dbname IS NULL THEN
       DISPLAY "Usage: mkcontact_main options ..."
       DISPLAY "   -d dbname"
       DISPLAY "   -f dbsrce"
       DISPLAY "   -o driver"
       DISPLAY "   -u user"
       DISPLAY "   -w pswd"
       DISPLAY "   -s : create sample data"
       EXIT PROGRAM 1
    END IF

    LET s = libutil.do_connect(dbname, dbsrce, dbdriv, uname, upswd)
    IF s !=0 THEN
       DISPLAY "ERROR:", s, " ", SQLERRMESSAGE
       EXIT PROGRAM 1
    END IF

    CALL mkcontacts.create_database("server",sample)

END MAIN
