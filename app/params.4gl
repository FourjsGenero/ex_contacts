IMPORT os
IMPORT util

IMPORT FGL libutil
IMPORT FGL password
IMPORT FGL dbsync_contact

PUBLIC DEFINE param_defaults RECORD
          user_id t_user_id
       END RECORD

PUBLIC DEFINE parameters RECORD
          user_id t_user_id,
          user_auth STRING, -- Encrypted
          cdb_format STRING,
          cdb_protocol STRING,
          cdb_host STRING,
          cdb_port INTEGER,
          cdb_gas CHAR(1),
          cdb_connector STRING,
          cdb_group STRING,
          auto_sync SMALLINT,
          sync_geoloc CHAR(1),
          see_all BOOLEAN,
          last_sync DATETIME YEAR TO FRACTION(3)
       END RECORD

PRIVATE FUNCTION mbox_ok(msg)
    DEFINE msg STRING
    CALL libutil.mbox_ok(%"contnote.title",msg)
END FUNCTION

PUBLIC FUNCTION params_cdb_url()
    DEFINE url STRING
    LET url = SFMT("%1://%2:%3",
                   parameters.cdb_protocol,
                   parameters.cdb_host,
                   parameters.cdb_port)
    IF parameters.cdb_gas=="Y" THEN
       LET url = url, SFMT("%1/ws/r%2/dbsync_contact_server",
                           "/"||parameters.cdb_connector,
                           "/"||parameters.cdb_group)
    END IF
    LET url = url, "/mobile/dbsync/", parameters.cdb_format
    RETURN url
END FUNCTION

PRIVATE FUNCTION change_password()
    DEFINE r SMALLINT,
           old_pwd STRING,
           new_pwd STRING,
           msg STRING
    WHILE TRUE
        -- Old and new passwords are entered in clear...
        CALL enter_password() RETURNING r, old_pwd, new_pwd
        IF r==-1 THEN
           EXIT WHILE
        END IF
        IF r==0 THEN
            CALL dbsync_contacts_set_sync_url( params_cdb_url() )
            CALL dbsync_contacts_set_sync_format( parameters.cdb_format )
            CALL dbsync_change_user_auth(
                        parameters.user_id,
                        libutil.user_auth_encrypt( old_pwd ),
                        libutil.user_auth_encrypt( new_pwd )
                 )
                 RETURNING r, msg
            IF r==0 THEN
               CALL mbox_ok(%"contacts.mess.pswdsucc")
               LET parameters.user_auth = libutil.user_auth_encrypt( new_pwd )
               CALL save_settings()
               EXIT WHILE
            ELSE
               CALL mbox_ok(%"contacts.mess.pswdfail")
            END IF
        END IF
    END WHILE
END FUNCTION

PRIVATE FUNCTION test_connection()
    DEFINE r INTEGER, url, msg STRING
    LET url = params_cdb_url()
    CALL dbsync_contacts_set_sync_url( url )
    CALL dbsync_contacts_set_sync_format( parameters.cdb_format )
    CALL dbsync_test_connection( parameters.user_id, parameters.user_auth )
         RETURNING r, msg
    IF r==0 THEN
       CALL mbox_ok(%"contacts.mess.connsucc")
    ELSE
       CALL mbox_ok(%"contacts.mess.connfail"||"\n"||url||":\n"||msg)
    END IF
    RETURN r
END FUNCTION

FUNCTION edit_settings(init)
    DEFINE init BOOLEAN
    DEFINE cdb_url STRING,
           tested BOOLEAN
    OPEN WINDOW w_params WITH FORM "params"
    LET cdb_url = params_cdb_url()
    LET int_flag = FALSE
    LET tested = (NOT init)
    INPUT BY NAME parameters.user_id,
                  parameters.cdb_format,
                  parameters.cdb_protocol,
                  parameters.cdb_host,
                  parameters.cdb_port,
                  parameters.cdb_gas,
                  parameters.cdb_connector,
                  parameters.cdb_group,
                  cdb_url,
                  parameters.auto_sync,
                  parameters.sync_geoloc
          WITHOUT DEFAULTS ATTRIBUTES(UNBUFFERED)
        BEFORE INPUT
           CALL DIALOG.setFieldActive("cdb_connector",parameters.cdb_gas=="Y")
           CALL DIALOG.setFieldActive("cdb_group",parameters.cdb_gas=="Y")
        ON CHANGE cdb_format, cdb_protocol, cdb_host, cdb_port,
                  cdb_gas, cdb_connector, cdb_group
           LET cdb_url = params_cdb_url()
           LET tested = FALSE
           CALL DIALOG.setFieldActive("cdb_connector",parameters.cdb_gas=="Y")
           CALL DIALOG.setFieldActive("cdb_group",parameters.cdb_gas=="Y")
        ON ACTION set_password
           CALL change_password()
        ON ACTION test_connection
           LET tested = (test_connection()==0)
        #ON ACTION gas_settings
        #   LET parameters.cdb_host = "192.168.1.34"
        #   LET parameters.cdb_port = 6394 -- When using GAS
        #   LET parameters.cdb_gas = "Y"
        AFTER INPUT
           IF NOT int_flag THEN
              IF NOT tested THEN
                 LET tested = (test_connection()==0)
                 IF NOT tested THEN NEXT FIELD CURRENT END IF
              END IF
           END IF
    END INPUT
    CLOSE WINDOW w_params
    IF parameters.user_id IS NULL AND int_flag THEN
       CALL mbox_ok(%"contacts.mess.reqparams")
       EXIT PROGRAM
    END IF
    RETURN (NOT int_flag)
END FUNCTION

PRIVATE FUNCTION get_settings_file()
    RETURN os.Path.join(os.Path.pwd(),"contacts.dat")
END FUNCTION

PUBLIC FUNCTION load_settings()
    DEFINE fn, data STRING,
           ch base.Channel,
           ft BOOLEAN
    LET fn = get_settings_file()
    LET ch = base.Channel.create()
    TRY
        CALL ch.openFile(fn,"r")
        LET data = ch.readLine()
        CALL util.JSON.parse( data, parameters )
        CALL ch.close()
        LET ft = FALSE
    CATCH
        LET ft = TRUE
    END TRY
    IF ft THEN
       LET parameters.user_id = param_defaults.user_id
       LET parameters.cdb_format = "json"
       LET parameters.cdb_protocol = "http"
       LET parameters.cdb_host = "10.0.2.2" -- (for Android Emulator)
       LET parameters.cdb_port = 6394
       LET parameters.cdb_gas = "N"
       LET parameters.cdb_connector = NULL
       LET parameters.cdb_group = NULL
       LET parameters.auto_sync = 0
       LET parameters.sync_geoloc = "Y"
       IF NOT edit_settings(TRUE) THEN
          RETURN -1
       END IF
       CALL save_settings()
       LET parameters.see_all   = FALSE
       LET parameters.last_sync = "1900-01-01 00:00:00"
       RETURN 0
    ELSE
       RETURN 1
    END IF
END FUNCTION

FUNCTION save_settings()
    DEFINE fn, data STRING,
           ch base.Channel
    LET data = util.JSON.stringify( parameters )
    LET fn = get_settings_file()
    LET ch = base.Channel.create()
    CALL ch.openFile(fn,"w")
    CALL ch.writeLine(data)
    CALL ch.close()
END FUNCTION
