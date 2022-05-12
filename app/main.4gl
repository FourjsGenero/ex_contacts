# TODO:  Check/improve photo file transfer

IMPORT os
IMPORT util

IMPORT FGL libutil
IMPORT FGL params
IMPORT FGL mkcontacts
IMPORT FGL dbsync_contact
IMPORT FGL contnotes

SCHEMA contacts

DEFINE contlist DYNAMIC ARRAY OF RECORD
         contact_num LIKE contact.contact_num,
         contact_rec_muser LIKE contact.contact_rec_muser,
         contact_rec_mtime LIKE contact.contact_rec_mtime,
         contact_rec_mstat LIKE contact.contact_rec_mstat,
         contact_name LIKE contact.contact_name,
         contact_valid LIKE contact.contact_valid,
         contact_street LIKE contact.contact_street,
         contact_city LIKE contact.contact_city,
         city_desc STRING,
         contact_num_m LIKE contact.contact_num_m,
         contact_num_w LIKE contact.contact_num_w,
         contact_num_h LIKE contact.contact_num_h,
         contact_user LIKE contact.contact_user,
         contact_loc_lon LIKE contact.contact_loc_lon,
         contact_loc_lat LIKE contact.contact_loc_lat,
         contact_photo_file STRING,
         short_desc STRING
     END RECORD
DEFINE contlistattr DYNAMIC ARRAY OF RECORD
         contact_num STRING,
         contact_rec_muser STRING,
         contact_rec_mtime STRING,
         contact_rec_mstat STRING,
         contact_name STRING,
         contact_valid STRING,
         contact_street STRING,
         contact_city STRING,
         city_desc STRING,
         contact_num_m STRING,
         contact_num_w STRING,
         contact_num_h STRING,
         contact_user STRING,
         contact_loc_lon STRING,
         contact_loc_lat STRING,
         contact_photo_file STRING,
         short_desc STRING
     END RECORD

DEFINE curr_contact RECORD
         contact_num LIKE contact.contact_num,
         contact_rec_muser LIKE contact.contact_rec_muser,
         contact_rec_mtime LIKE contact.contact_rec_mtime,
         contact_rec_mstat LIKE contact.contact_rec_mstat,
         contact_name LIKE contact.contact_name,
         contact_valid LIKE contact.contact_valid,
         contact_street LIKE contact.contact_street,
         contact_city LIKE contact.contact_city,
         city_desc STRING,
         contact_num_m LIKE contact.contact_num_m,
         contact_num_w LIKE contact.contact_num_w,
         contact_num_h LIKE contact.contact_num_h,
         status_label STRING,
         contact_user LIKE contact.contact_user,
         contact_loc_lon LIKE contact.contact_loc_lon,
         contact_loc_lat LIKE contact.contact_loc_lat,
         contact_photo_mtime LIKE contact.contact_photo_mtime,
         contact_photo_file STRING
     END RECORD

CONSTANT BFN_DIRECTORY = "bfn_tmp",
         ANONYMOUS_IMAGE_FILE = "./images/anonymous.png"

DEFINE source VARCHAR(300)

MAIN
    DEFER INTERRUPT
    CALL initialize_application()
    CALL open_database()
    CALL initialize_parameters()
    CALL load_contacts()
    CALL open_main_form()
    CALL contact_list()
    CALL terminate_application()
END MAIN

PRIVATE FUNCTION initialize_application()
    OPTIONS INPUT WRAP, FIELD ORDER FORM
    CALL add_presentation_styles()
    CALL my_startlog("contacts.log")
    CALL ui.Interface.loadActionDefaults("contacts")
END FUNCTION

PRIVATE FUNCTION open_database()
    DEFINE basedir, dbfile, connstr VARCHAR(256)
    -- source is defined as module variable, so we can delete it for tests
    LET dbfile = "contacts.dbs"
    IF base.Application.isMobile() THEN
        LET basedir = os.Path.pwd() -- Documents dir
        LET source = os.Path.join(basedir, dbfile)
    ELSE -- In development mode on server
        LET basedir = fgl_getenv("USERDBDIR")
        IF basedir IS NULL THEN
           LET param_defaults.user_id = "max"
           DISPLAY "WARNING: USERDBDIR not set, using current dir for dbfile"
           LET source = dbfile
        ELSE
           LET source = os.Path.join(basedir, dbfile)
        END IF
    END IF
    LET connstr = SFMT("contacts+source='%1'", escape_backslashes(source) )
    IF NOT base.Application.isMobile() THEN
       LET connstr = connstr, ",driver='dbmsqt'"
    END IF
    CALL my_errorlog(SFMT("open_database: %1", connstr))
    IF os.Path.exists(source) THEN
        CONNECT TO connstr AS "c1"
    ELSE
        CALL create_empty_file(source)
        CONNECT TO connstr AS "c1"
        CALL mkcontacts.create_database("mobile",FALSE)
    END IF
END FUNCTION

FUNCTION escape_backslashes(str)
    DEFINE str STRING
    DEFINE buf base.StringBuffer
    LET buf = base.StringBuffer.create()
    CALL buf.append(str)
    CALL buf.replace("\\","\\\\",0)
    RETURN buf.toString()
END FUNCTION

PRIVATE FUNCTION close_database()
    DISCONNECT "c1"
END FUNCTION

PRIVATE FUNCTION initialize_parameters()
    DEFINE r BOOLEAN
    CASE load_settings()
       WHEN -1 -- First time, but param input was canceled
         EXIT PROGRAM
       WHEN 0 -- First time
         -- Must be connected!!!
         CALL mbox_ok(%"contacts.mess.firstsync")
         LET r = synchronize(TRUE,TRUE)
       OTHERWISE -- Params loaded, continue
    END CASE
END FUNCTION

PRIVATE FUNCTION open_main_form()
    OPEN FORM f1 FROM "contlist"
    DISPLAY FORM f1
    CALL set_title()
END FUNCTION

PRIVATE FUNCTION set_title()
    DEFINE w ui.Window,
           title STRING
    LET title = SFMT("%1 / %2", %"contacts.title", parameters.user_id )
    LET w = ui.Window.getCurrent()
    CALL w.setText( title )
    CALL ui.Interface.setText( title )
END FUNCTION

PRIVATE FUNCTION contact_list()
    DEFINE curr_row INTEGER,
           last_idle, curr_idle DATETIME YEAR TO SECOND,
           ts_diff, ts_max INTERVAL SECOND(9) TO SECOND,
           tmp STRING

    LET last_idle = CURRENT

    DISPLAY ARRAY contlist TO sr.*
        ATTRIBUTES(UNBUFFERED,
                   DOUBLECLICK=update,
                   ACCESSORYTYPE=DISCLOSUREINDICATOR,
                   ACCEPT=FALSE, CANCEL=FALSE)
        BEFORE DISPLAY
           CALL DIALOG.setArrayAttributes("sr",contlistattr)
--ON ACTION exit EXIT PROGRAM 1
        ON IDLE 30
           CALL update_geoloc_for_user(FALSE)
           LET curr_idle = CURRENT YEAR TO SECOND
           LET ts_diff = curr_idle - last_idle
           IF parameters.auto_sync > 0 THEN
              LET tmp = parameters.auto_sync
              LET ts_max = tmp
              IF ts_diff >= ts_max THEN
                 MESSAGE %"contacts.mess.sync"
                 CALL ui.Interface.refresh()
                 LET curr_row = arr_curr()
                 IF synchronize(FALSE, TRUE) THEN
                    CALL DIALOG.setCurrentRow("sr", curr_row)
                 END IF
                 LET last_idle = curr_idle
              END IF
           END IF
        ON APPEND
           CALL edit_contact(arr_curr(), TRUE)
           -- Reload to get it ordered?
        ON UPDATE
           -- In case if we get BEFORE ROW + ON UPDATE at the same time, we must check
           -- again because the action may not be disabled
           IF NOT dbsync_marked_for_garbage(contlist[arr_curr()].contact_rec_mstat) THEN
              CALL edit_contact(arr_curr(), FALSE)
           ELSE
              ERROR %"contacts.error.cantupd1"
              LET int_flag = TRUE
           END IF
        ON DELETE
           -- In case if we get BEFORE ROW + ON DELETE at the same time, we must check
           -- again because the action may not be disabled
           IF NOT dbsync_marked_for_deletion(contlist[arr_curr()].contact_rec_mstat) THEN
              CALL remove_contact(TRUE,arr_curr())
           ELSE
              ERROR %"contacts.error.cantdel1"
              LET int_flag = TRUE
           END IF
        ON ACTION sync
           IF synchronize(FALSE,TRUE) THEN
              CALL DIALOG.setCurrentRow("sr",1)
           END IF
        ON ACTION options
           CALL contlist_options(DIALOG)
        ON ACTION close
           EXIT DISPLAY
    END DISPLAY

END FUNCTION

PRIVATE FUNCTION terminate_application()
    DEFINE r BOOLEAN
    IF mbox_yn(%"contacts.mess.syncnow") THEN
       LET r = synchronize(FALSE,FALSE)
    END IF
    CALL save_settings()
    CALL libutil.bfn_cleanup()
   EXIT PROGRAM 0
END FUNCTION

PRIVATE FUNCTION mbox_ok(msg)
    DEFINE msg STRING
    CALL libutil.mbox_ok(%"contacts.title",msg)
END FUNCTION

PRIVATE FUNCTION mbox_yn(msg)
    DEFINE msg STRING
    RETURN libutil.mbox_yn(%"contacts.title",msg)
END FUNCTION

PRIVATE FUNCTION contlist_options(d)
    DEFINE d ui.Dialog
    DEFINE sync SMALLINT
    OPEN WINDOW w_options_1 WITH FORM "options1"
    MENU "options1"
        ON ACTION geoloc
           CALL update_geoloc_for_user(TRUE)
           CALL show_map()
        ON ACTION call
           CALL call_contact(d.getCurrentRow("sr"))
        ON ACTION sync
           LET sync = 1
           EXIT MENU
        ON ACTION settings
           IF edit_settings(FALSE) THEN
              CALL set_title()
              CALL save_settings()
           END IF
        ON ACTION quit
           CALL terminate_application()
        ON ACTION togglepha
           LET parameters.see_all = NOT parameters.see_all
           CALL load_contacts()
           CALL d.setCurrentRow("sr",1)
        ON ACTION cleargarb
           CALL clear_garbage(d)
        ON ACTION syncfirst
           LET sync = 2
           EXIT MENU
        ON ACTION synclog
           CALL dbsynclog_show()
        ON ACTION stress
           MENU "Stress test" ATTRIBUTES(STYLE="dialog")
               COMMAND "More"  CALL stress_test(d)
               COMMAND "Clean" CALL stress_clean()
           END MENU
        ON ACTION cancel ATTRIBUTES(TEXT=%"contacts.contlist_options_menu.cancel")
           EXIT MENU
    END MENU
    CLOSE WINDOW w_options_1
    IF sync>0 THEN
       IF synchronize((sync==2),TRUE) THEN
          CALL d.setCurrentRow("sr",1)
       END IF
    END IF
END FUNCTION

PRIVATE FUNCTION clear_garbage(d)
    DEFINE d ui.Dialog
    CALL dbsync_contact.delete_garbage_contact()
    CALL load_contacts()
    CALL d.setCurrentRow("sr",1)
END FUNCTION

PRIVATE FUNCTION stress_clean()
    DEFINE x INTEGER, r BOOLEAN
    FOR x = 1 TO contlist.getLength()
        IF contlist[x].contact_name LIKE "Upd:%"
        OR contlist[x].contact_name LIKE "New:%" THEN
           CALL remove_contact(FALSE,x)
        END IF
    END FOR
    LET r = synchronize(FALSE,FALSE)
END FUNCTION

PRIVATE FUNCTION set_curr_contact_minfo(pmt)
    DEFINE pmt BOOLEAN
    LET curr_contact.contact_rec_muser = parameters.user_id
    LET curr_contact.contact_rec_mtime = util.Datetime.getCurrentAsUTC()
    IF pmt THEN
       LET curr_contact.contact_photo_mtime = curr_contact.contact_rec_mtime
    END IF
END FUNCTION

PRIVATE FUNCTION stress_test(d)
    DEFINE d ui.Dialog
    DEFINE x, row INTEGER,
           r BOOLEAN,
           tmp_byte BYTE
    IF contlist.getLength() == 0 THEN RETURN END IF
    CALL clear_garbage(d) -- avoid updates of garbage records here
    LET row = 0
    FOR x=1 TO 30
        LET row = row+1
        IF row > contlist.getLength() THEN
           LET row = 1
        END IF
        CALL controw_to_contrec(row)
        CALL set_curr_contact_minfo(TRUE)
        IF x MOD 10 != 0 THEN
          LET curr_contact.contact_rec_mstat = "U1"
          LET curr_contact.contact_name = SFMT("Upd: (%1) %2", parameters.user_id, CURRENT HOUR TO FRACTION(5))
--DISPLAY "UPDATE: ", curr_contact.contact_num
          UPDATE contact SET
                 contact_rec_muser = curr_contact.contact_rec_muser,
                 contact_rec_mtime = curr_contact.contact_rec_mtime,
                 contact_rec_mstat = curr_contact.contact_rec_mstat,
                 contact_name = curr_contact.contact_name
            WHERE contact_num = curr_contact.contact_num
        ELSE
--DISPLAY "DELETE: ", curr_contact.contact_num
          LET curr_contact.contact_rec_mstat = "D"
          UPDATE contact SET
                 contact_rec_muser = curr_contact.contact_rec_muser,
                 contact_rec_mtime = curr_contact.contact_rec_mtime,
                 contact_rec_mstat = curr_contact.contact_rec_mstat,
                 contact_name = curr_contact.contact_name
            WHERE contact_num = curr_contact.contact_num
        END IF
        IF x MOD 3 == 1 THEN
          LET curr_contact.contact_rec_mstat = "N"
          LET curr_contact.contact_num = libutil.sequence_mobile_new("contact","contact_num")
          LET curr_contact.contact_name = SFMT("New: (%1) %2", parameters.user_id, CURRENT HOUR TO FRACTION(5))
          LET curr_contact.contact_valid = "N"
          LET curr_contact.contact_user = v_undef
          LET curr_contact.contact_city = 1001 -- Paris
--DISPLAY "INSERT: ", curr_contact.contact_num
          IF curr_contact.contact_photo_file != ANONYMOUS_IMAGE_FILE THEN
             LOCATE tmp_byte IN FILE curr_contact.contact_photo_file
          ELSE
             LOCATE tmp_byte IN MEMORY
             INITIALIZE tmp_byte TO NULL
          END IF
          INSERT INTO contact VALUES (
                      curr_contact.contact_num,
                      curr_contact.contact_rec_muser,
                      curr_contact.contact_rec_mtime,
                      curr_contact.contact_rec_mstat,
                      curr_contact.contact_name,
                      curr_contact.contact_valid,
                      curr_contact.contact_street,
                      curr_contact.contact_city,
                      curr_contact.contact_num_m,
                      curr_contact.contact_num_w,
                      curr_contact.contact_num_h,
                      curr_contact.contact_user,
                      curr_contact.contact_loc_lon,
                      curr_contact.contact_loc_lat,
                      curr_contact.contact_photo_mtime,
                      tmp_byte
                      )
        END IF
        IF x MOD 5 == 0 THEN
           --DISPLAY "SYNC!"
           LET r = synchronize(FALSE,FALSE)
           --SLEEP 1
        END IF
    END FOR
END FUNCTION

PRIVATE FUNCTION call_contact(row)
    DEFINE row INTEGER
    DEFINE num, res, cmt_m, cmt_h, cmt_w STRING

    LET cmt_m = "("||contlist[row].contact_num_m||")"
    LET cmt_h = "("||contlist[row].contact_num_h||")"
    LET cmt_w = "("||contlist[row].contact_num_w||")"
    MENU %"contacts.contlist_options_menu.call"
      ATTRIBUTES(STYLE="popup")
        COMMAND %"contacts.contlist_options_menu.call.mobile" cmt_m
           LET num = contlist[row].contact_num_m
        COMMAND %"contacts.contlist_options_menu.call.home" cmt_h
           LET num = contlist[row].contact_num_w
        COMMAND %"contacts.contlist_options_menu.call.work" cmt_w
           LET num = contlist[row].contact_num_h
        ON ACTION cancel
           LET num = NULL
    END MENU
    IF num IS NOT NULL THEN
       WHENEVER ERROR CONTINUE
       LET num = "tel:"||num
       CALL ui.Interface.frontCall("standard","launchurl",[num],[res])
       WHENEVER ERROR STOP
       IF status THEN
          ERROR "Could not initiate call: ", status
       END IF
    END IF

END FUNCTION

PRIVATE FUNCTION synchronize(first_sync, with_ui)
    DEFINE first_sync, with_ui BOOLEAN
    DEFINE s, c, t INTEGER, msg STRING
    CALL dbsync_contacts_set_sync_url( params_cdb_url() )
    CALL dbsync_contacts_set_sync_format( parameters.cdb_format )
    CALL dbsync_sync_contacts_send( first_sync, parameters.user_id, parameters.user_auth )
         RETURNING s, msg
    IF s!=0 AND with_ui IS NOT NULL THEN
       CALL mbox_ok(SFMT(%"contacts.mess.syncfail",s,msg))
       RETURN FALSE
    END IF
    LET t = dbsync_get_download_count()
    EXECUTE IMMEDIATE "VACUUM"
    EXECUTE IMMEDIATE "PRAGMA foreign_key=ON"
    IF NOT with_ui OR t<=2 THEN
       CALL dbsync_sync_contacts_download( first_sync, parameters.user_id, parameters.user_auth, -1 )
            RETURNING s, msg
       IF s<0 THEN
          CALL mbox_ok(SFMT(%"contacts.mess.syncfail",s,msg))
          RETURN FALSE
       END IF
    ELSE
       -- Get visual feedback
       LET s = 0
       LET c = 0
       LET int_flag = FALSE
       WHILE s==0 -- Stop when s==1
          CALL dbsync_sync_contacts_download( first_sync, parameters.user_id, parameters.user_auth, 3 )
               RETURNING s, msg
          IF s<0 THEN
             CALL mbox_ok(SFMT(%"contacts.mess.syncfail",s,msg))
             RETURN FALSE
          END IF
          MESSAGE SFMT(%"contacts.mess.downloaded",c,t) CALL ui.Interface.refresh()
          LET c = c + 3
          IF s==1 THEN EXIT WHILE END IF
          IF int_flag THEN
             CALL mbox_ok(%"contacts.mess.syncint")
             EXIT WHILE
          END IF
       END WHILE
       IF int_flag THEN
          LET int_flag = FALSE
       ELSE
          MESSAGE SFMT(%"contacts.mess.downloaded",t,t) CALL ui.Interface.refresh()
       END IF
    END IF
    CALL dbsync_send_return_receipt(parameters.user_id, parameters.user_auth)
         RETURNING s, msg
    IF s<0 THEN
       CALL mbox_ok(SFMT(%"contacts.mess.syncfail",s,msg))
       RETURN FALSE
    END IF
    CALL load_contacts()
    LET parameters.last_sync = CURRENT
    CALL save_settings()
    IF with_ui THEN
       IF dbsynclog_count()>0 THEN
          IF mbox_yn(%"contacts.mess.syncprobs") THEN
             CALL dbsynclog_show()
          END IF
       END IF
    END IF
    RETURN TRUE
END FUNCTION

PRIVATE FUNCTION remove_contact(interactive, row)
    DEFINE interactive BOOLEAN
    DEFINE row INT
    IF interactive
       AND NOT dbsync_marked_as_unsync(contlist[row].contact_rec_mstat)
       AND contlist[row].contact_valid == "Y" THEN
       IF NOT mbox_yn(%"contacts.mess.delvalid") THEN
          LET int_flag = TRUE
          RETURN
       END IF
    END IF
    -- New, AddFail, UpdMiss, DelMiss and Phantom marked records can be removed directly
    IF contlist[row].contact_rec_mstat=="N"
       OR dbsync_marked_as_unsync(contlist[row].contact_rec_mstat) THEN
       DELETE FROM contnote
              WHERE contnote_contact = contlist[row].contact_num
       DELETE FROM contact
              WHERE contact_num = contlist[row].contact_num
    ELSE
       LET contlist[row].contact_rec_muser = parameters.user_id
       LET contlist[row].contact_rec_mtime = util.Datetime.getCurrentAsUTC()
       CASE contlist[row].contact_rec_mstat
        WHEN "U1" LET contlist[row].contact_rec_mstat = "T1"
        WHEN "U2" LET contlist[row].contact_rec_mstat = "T2"
        OTHERWISE LET contlist[row].contact_rec_mstat = "D"
       END CASE
       UPDATE contact SET
           contact_rec_muser = contlist[row].contact_rec_muser,
           contact_rec_mtime = contlist[row].contact_rec_mtime,
           contact_rec_mstat = contlist[row].contact_rec_mstat
          WHERE contact_num = contlist[row].contact_num
       IF parameters.see_all THEN
          LET contlist[row].short_desc = get_short_desc(contlist[row].contact_num,
                                                        contlist[row].contact_rec_mstat,
                                                        contlist[row].contact_city,
                                                        contlist[row].city_desc)
          LET contlistattr[row].short_desc = dbsync_mstat_color(contlist[row].contact_rec_mstat)
          LET int_flag = TRUE
       END IF
    END IF
END FUNCTION

PRIVATE FUNCTION zoom_city()
    TYPE t_city RECORD
               num INTEGER,
               name VARCHAR(50),
               country VARCHAR(50)
           END RECORD
    DEFINE rec t_city, arr DYNAMIC ARRAY OF t_city,
           row INTEGER, r_num INTEGER, r_desc VARCHAR(60),
           wp VARCHAR(200)

    LET wp=dbsync_contact.datafilter_city -- Set by sync
    DECLARE c_zoom_city CURSOR FROM
     "SELECT city_num, city_name, city_country"||
     " FROM city"||
     IIF(wp IS NULL, " ", " WHERE "||wp) ||
     " ORDER BY city_name"
    FOREACH c_zoom_city INTO rec.*
       LET arr[arr.getLength()+1].* = rec.*
       IF rec.num == curr_contact.contact_city THEN
          LET row = arr.getLength()
       END IF
    END FOREACH
    OPEN WINDOW w_zoom_city WITH FORM "list1" ATTRIBUTES(STYLE="dialog",TEXT=%"citylist.title")
    LET int_flag=FALSE
    DISPLAY ARRAY arr TO sr.* ATTRIBUTES(DOUBLECLICK=accept)
        BEFORE DISPLAY
          CALL DIALOG.setCurrentRow("sr",row)
    END DISPLAY
    IF NOT int_flag THEN
       LET r_num = arr[arr_curr()].num
       LET r_desc = arr[arr_curr()].name||', '||arr[arr_curr()].country
    ELSE
       LET r_num = curr_contact.contact_city
       LET r_desc = curr_contact.city_desc
    END IF
    CLOSE WINDOW w_zoom_city
    RETURN r_num, r_desc
END FUNCTION

PRIVATE FUNCTION check_city()
    DEFINE r_num INTEGER, r_desc VARCHAR(60)
    DEFINE name VARCHAR(60)
    LET name = curr_contact.city_desc||"%"
    SELECT city_num, city_name||", "||city_country
       INTO r_num, r_desc
       FROM city
      WHERE city_name||", "||city_country LIKE name
         OR city_name LIKE name
    IF sqlca.sqlcode==NOTFOUND THEN
       LET r_num = -1
       LET r_desc = curr_contact.city_desc
    END IF
    RETURN r_num, r_desc
END FUNCTION

PRIVATE FUNCTION byte_image_file_name(num, ts)
    DEFINE num INTEGER, ts DATETIME YEAR TO FRACTION(3)
    DEFINE id, fs STRING, s INTEGER
    LET fs = os.Path.join(BFN_DIRECTORY, "photo_%1_%2")
    IF NOT os.Path.exists(BFN_DIRECTORY) THEN
       LET s = os.Path.mkdir(BFN_DIRECTORY)
    END IF
    IF num < 0 THEN -- local records have negative numbers
       LET id = "m_"||(-num)
    ELSE
       LET id = num
    END IF
    RETURN libutil.bfn_get(fs, id, ts)
END FUNCTION

PRIVATE FUNCTION controw_to_contrec(row)
    DEFINE row INT
    LET curr_contact.contact_num        = contlist[row].contact_num
    LET curr_contact.contact_rec_muser  = contlist[row].contact_rec_muser
    LET curr_contact.contact_rec_mtime  = contlist[row].contact_rec_mtime
    LET curr_contact.contact_rec_mstat  = contlist[row].contact_rec_mstat
    LET curr_contact.contact_name       = contlist[row].contact_name
    LET curr_contact.contact_valid      = contlist[row].contact_valid
    LET curr_contact.contact_street     = contlist[row].contact_street
    LET curr_contact.contact_city       = contlist[row].contact_city
    LET curr_contact.city_desc          = contlist[row].city_desc
    LET curr_contact.contact_num_m      = contlist[row].contact_num_m
    LET curr_contact.contact_num_w      = contlist[row].contact_num_w
    LET curr_contact.contact_num_h      = contlist[row].contact_num_h
    LET curr_contact.contact_user       = contlist[row].contact_user
    LET curr_contact.contact_loc_lon    = contlist[row].contact_loc_lon
    LET curr_contact.contact_loc_lat    = contlist[row].contact_loc_lat
    LET curr_contact.status_label       = dbsync_mstat_desc(curr_contact.contact_rec_mstat)
    LET curr_contact.contact_photo_file = contlist[row].contact_photo_file
END FUNCTION

PRIVATE FUNCTION contrec_to_controw(row, new)
    DEFINE row INT, new BOOLEAN
    LET new = NULL -- Unused for now
    LET contlist[row].contact_num = curr_contact.contact_num
    LET contlist[row].contact_rec_muser = curr_contact.contact_rec_muser
    LET contlist[row].contact_rec_mtime = curr_contact.contact_rec_mtime
    LET contlist[row].contact_rec_mstat = curr_contact.contact_rec_mstat
    LET contlist[row].contact_name = curr_contact.contact_name
    LET contlist[row].contact_valid = curr_contact.contact_valid
    LET contlist[row].contact_street = curr_contact.contact_street
    LET contlist[row].contact_city = curr_contact.contact_city
    LET contlist[row].city_desc = curr_contact.city_desc
    LET contlist[row].contact_num_m = curr_contact.contact_num_m
    LET contlist[row].contact_num_w = curr_contact.contact_num_w
    LET contlist[row].contact_num_h = curr_contact.contact_num_h
    LET contlist[row].contact_user = curr_contact.contact_user
    LET contlist[row].contact_loc_lon = curr_contact.contact_loc_lon
    LET contlist[row].contact_loc_lat = curr_contact.contact_loc_lat
    LET contlist[row].contact_photo_file = curr_contact.contact_photo_file
    LET contlist[row].short_desc = get_short_desc(contlist[row].contact_num,
                                                  contlist[row].contact_rec_mstat,
                                                  contlist[row].contact_city,
                                                  contlist[row].city_desc)
    LET contlistattr[row].short_desc = dbsync_mstat_color(curr_contact.contact_rec_mstat)
END FUNCTION

PRIVATE FUNCTION edit_contact(row, new)
    DEFINE row INT, new BOOLEAN
    DEFINE photo_touched BOOLEAN,
           tmp_byte BYTE

    IF new THEN
       INITIALIZE curr_contact.* TO NULL
       LET curr_contact.contact_num = libutil.sequence_mobile_new("contact","contact_num")
       LET curr_contact.contact_name = "<Contact "||CURRENT HOUR TO FRACTION(3)||">"
       LET curr_contact.contact_valid = "N"
       LET curr_contact.contact_city = 1000 -- undefined
       LET curr_contact.city_desc = v_undef_text
       LET curr_contact.contact_user = v_undef
       LET curr_contact.contact_photo_file = ANONYMOUS_IMAGE_FILE
    ELSE
       CALL controw_to_contrec(row)
    END IF

    OPEN WINDOW w_contact WITH FORM "contform"

    LET int_flag = FALSE
    INPUT BY NAME curr_contact.* WITHOUT DEFAULTS
          ATTRIBUTES(UNBUFFERED)

        ON ACTION notes
           CALL edit_notes(parameters.user_id, curr_contact.contact_num)

        ON ACTION photo
           CALL contform_photo_options(DIALOG)

        ON ACTION options
           CALL contform_options(DIALOG, row)

        --ON ACTION zoom INFIELD city_desc
        ON ACTION zoom
           CALL zoom_city() RETURNING curr_contact.contact_city,
                                      curr_contact.city_desc
           IF NOT int_flag THEN
              CALL DIALOG.setFieldTouched("contact_city", TRUE)
           END IF

        AFTER FIELD city_desc
           IF curr_contact.city_desc IS NOT NULL THEN
              CALL check_city()
                   RETURNING curr_contact.contact_city,
                             curr_contact.city_desc
              IF sqlca.sqlcode==NOTFOUND THEN
                 ERROR %"contacts.error.invcity"
                 NEXT FIELD CURRENT
              END IF
           END IF

        AFTER INPUT
           IF int_flag AND DIALOG.getFieldTouched("formonly.*") THEN
              IF NOT mbox_yn(%"contacts.mess.modlost") THEN
                 LET int_flag = FALSE
                 CONTINUE INPUT
              END IF
           END IF
           IF NOT int_flag THEN
              IF new OR DIALOG.getFieldTouched("formonly.*") THEN
                 LET photo_touched = DIALOG.getFieldTouched("formonly.contact_photo_file")
                 CALL set_curr_contact_minfo(photo_touched)
                 CASE
                   WHEN new OR curr_contact.contact_rec_mstat MATCHES "[NC]"
                      LET curr_contact.contact_rec_mstat = "N"
                   WHEN curr_contact.contact_rec_mstat == "P" -- phantom modified = new
                      LET curr_contact.contact_rec_mstat = "N"
                   WHEN curr_contact.contact_rec_mstat == "M" -- update conflict, read-only
                      LET curr_contact.contact_rec_mstat = "M"
                   OTHERWISE
                      -- Different update status to avoid sync of unchanged picture
                      LET curr_contact.contact_rec_mstat = IIF(photo_touched,"U1","U2")
                 END CASE
                 WHENEVER ERROR CONTINUE
                 IF curr_contact.contact_photo_file != ANONYMOUS_IMAGE_FILE THEN
                    LOCATE tmp_byte IN FILE curr_contact.contact_photo_file
                 ELSE
                    LOCATE tmp_byte IN MEMORY
                    INITIALIZE tmp_byte TO NULL
                 END IF
                 IF new THEN
                    INSERT INTO contact VALUES (
                      curr_contact.contact_num,
                      curr_contact.contact_rec_muser,
                      curr_contact.contact_rec_mtime,
                      curr_contact.contact_rec_mstat,
                      curr_contact.contact_name,
                      curr_contact.contact_valid,
                      curr_contact.contact_street,
                      curr_contact.contact_city,
                      curr_contact.contact_num_m,
                      curr_contact.contact_num_w,
                      curr_contact.contact_num_h,
                      curr_contact.contact_user,
                      curr_contact.contact_loc_lon,
                      curr_contact.contact_loc_lat,
                      curr_contact.contact_photo_mtime,
                      tmp_byte
                      )
                 ELSE
                    UPDATE contact SET
                      contact_rec_muser = curr_contact.contact_rec_muser,
                      contact_rec_mtime = curr_contact.contact_rec_mtime,
                      contact_rec_mstat = curr_contact.contact_rec_mstat,
                      contact_name = curr_contact.contact_name,
                      contact_valid = curr_contact.contact_valid,
                      contact_street = curr_contact.contact_street,
                      contact_city = curr_contact.contact_city,
                      contact_num_m = curr_contact.contact_num_m,
                      contact_num_w = curr_contact.contact_num_w,
                      contact_num_h = curr_contact.contact_num_h,
                      contact_user = curr_contact.contact_user,
                      contact_loc_lon = curr_contact.contact_loc_lon,
                      contact_loc_lat = curr_contact.contact_loc_lat,
                      contact_photo_mtime = curr_contact.contact_photo_mtime,
                      contact_photo = tmp_byte
                     WHERE contact_num = curr_contact.contact_num
                 END IF
                 WHENEVER ERROR STOP
                 IF sqlca.sqlcode==0 THEN
                    LET curr_contact.status_label = dbsync_mstat_desc(curr_contact.contact_rec_mstat)
                    CALL contrec_to_controw(row, new)
                 ELSE
                    ERROR sqlca.sqlcode||":"||SQLERRMESSAGE
                    NEXT FIELD CURRENT
                 END IF
              END IF
           END IF

    END INPUT

    CLOSE WINDOW w_contact

END FUNCTION

PRIVATE FUNCTION get_photo(oper, d)
    DEFINE oper STRING, d ui.Dialog
    DEFINE fe_path, vm_path STRING
    CALL ui.Interface.frontCall("mobile",oper,[],fe_path)
    IF fe_path IS NOT NULL THEN
       CALL set_curr_contact_minfo(TRUE)
       LET vm_path = byte_image_file_name(
                         curr_contact.contact_num,
                         curr_contact.contact_rec_mtime
                     )
       CALL fgl_getfile( fe_path, vm_path )
       LET curr_contact.contact_photo_file = vm_path
       CALL d.setFieldTouched("contact_photo_file", TRUE)
    END IF
END FUNCTION

PRIVATE FUNCTION contform_photo_options(d)
    DEFINE d ui.Dialog
    MENU %"contacts.contform_options_menu.title"
            ATTRIBUTES(STYLE="popup")
        COMMAND %"contacts.contform_options_menu.take_photo"
           CALL get_photo("takePhoto", d)
        COMMAND %"contacts.contform_options_menu.choose_photo"
           CALL get_photo("choosePhoto", d)
        COMMAND %"contacts.contform_options_menu.clear_photo"
           LET curr_contact.contact_photo_file = ANONYMOUS_IMAGE_FILE
           CALL d.setFieldTouched("contact_photo_file", TRUE)
        COMMAND %"contacts.contform_options_menu.cancel"
           EXIT MENU
    END MENU
END FUNCTION

PRIVATE FUNCTION contform_options(d, row)
    DEFINE d ui.Dialog, row INTEGER
    MENU %"contacts.contform_options_menu.title"
            ATTRIBUTES(STYLE="popup")
        BEFORE MENU
           IF NOT dbsync_marked_for_deletion(curr_contact.contact_rec_mstat) THEN
              HIDE OPTION %"contacts.contform_options_menu.undelete"
           END IF
        COMMAND %"contacts.contform_options_menu.undelete"
           CALL contact_undelete(d)
        COMMAND %"contacts.contform_options_menu.photo"
           CALL contform_photo_options(d)
        COMMAND %"contacts.contform_options_menu.bind_user"
           CALL bind_user(row)
        COMMAND %"contacts.contform_options_menu.cancel"
           EXIT MENU
    END MENU
END FUNCTION

PRIVATE FUNCTION contact_undelete(d)
    DEFINE d ui.Dialog
    IF NOT mbox_yn(%"contform.mess.undelete") THEN RETURN END IF
    CASE curr_contact.contact_rec_mstat
         WHEN "T1" LET curr_contact.contact_rec_mstat = "U1"
         WHEN "T2" LET curr_contact.contact_rec_mstat = "U2"
         WHEN "D"  LET curr_contact.contact_rec_mstat = "S"
         OTHERWISE CALL mbox_ok("Invalid undelete mode") EXIT PROGRAM 1
    END CASE
    CALL d.setFieldTouched("contact_rec_mstat",TRUE)
    LET curr_contact.status_label = dbsync_mstat_desc(curr_contact.contact_rec_mstat)
END FUNCTION

PRIVATE FUNCTION contact_lookup_for_num(num)
    DEFINE num INTEGER
    DEFINE i INTEGER
    FOR i=1 TO contlist.getLength()
        IF contlist[i].contact_num == num THEN
           RETURN i
        END IF
    END FOR
    RETURN 0
END FUNCTION

PRIVATE FUNCTION contact_lookup_for_user(uid)
    DEFINE uid t_user_id
    DEFINE i INTEGER
    FOR i=1 TO contlist.getLength()
        IF contlist[i].contact_user == uid THEN
           RETURN i
        END IF
    END FOR
    RETURN 0
END FUNCTION

PRIVATE FUNCTION bind_user(row)
    DEFINE row INTEGER
    DEFINE r, i INTEGER, msg STRING, old_cnum INTEGER
    IF NOT mbox_yn(%"contform.mess.bind_user") THEN RETURN END IF
    CALL dbsync_contacts_set_sync_url( params_cdb_url() )
    CALL dbsync_contacts_set_sync_format( parameters.cdb_format )
    CALL dbsync_bind_user( parameters.user_id, parameters.user_auth, curr_contact.contact_num )
         RETURNING r, msg, old_cnum
    IF r == 0 THEN
       CALL mbox_ok(%"contacts.mess.busucc")
       LET curr_contact.contact_user = parameters.user_id
       LET contlist[row].contact_user = parameters.user_id
       LET i = contact_lookup_for_num(old_cnum)
       IF i > 0 THEN
          LET contlist[i].contact_user = v_undef
          LET contlist[i].contact_loc_lon = NULL
          LET contlist[i].contact_loc_lat = NULL
       END IF
    ELSE
       CALL mbox_ok(msg)
    END IF
    -- RETURN r
END FUNCTION

-- Can be called by ON IDLE!
-- Sends command to server to udpate the central db.
-- DECIMAL(10,6): 6 decimal places = 0.11 m precision.
PRIVATE FUNCTION update_geoloc_for_user(forced)
    DEFINE forced BOOLEAN
    DEFINE status STRING, lat, lon DECIMAL(10,6)
    DEFINE i INTEGER, r INTEGER, msg STRING
    CONSTANT f = "----&.&&&&&"
    LET i = contact_lookup_for_user(parameters.user_id)
    IF i <= 0 THEN RETURN END IF
    IF NOT forced AND parameters.sync_geoloc=="N" THEN RETURN END IF
    TRY
       CALL ui.Interface.frontCall("mobile", "getGeolocation", [], [status, lat, lon] )
    CATCH
       LET status="notmobile"
    END TRY
    IF status=="ok" THEN
       IF  (contlist[i].contact_loc_lon USING f) == (lon USING f)
       AND (contlist[i].contact_loc_lat USING f) == (lat USING f) THEN
           RETURN
       END IF
       CALL dbsync_contacts_set_sync_url( params_cdb_url() )
       CALL dbsync_contacts_set_sync_format( parameters.cdb_format )
       CALL dbsync_update_geoloc( parameters.user_id, parameters.user_auth, lon, lat )
            RETURNING r, msg
       IF r==0 THEN
          LET contlist[i].contact_loc_lon = lon
          LET contlist[i].contact_loc_lat = lat
          IF curr_contact.contact_num = contlist[i].contact_num THEN
             LET curr_contact.contact_loc_lon = lon
             LET curr_contact.contact_loc_lat = lat
          END IF
       END IF
    END IF
END FUNCTION

PRIVATE FUNCTION show_map()
    DEFINE map_url STRING,
           zoom INTEGER,
           type CHAR(1),
           cnum INTEGER
    CONSTANT def_zoom = 14, min_zoom = 3, max_zoom = 17

    LET type = "A"
    LET cnum = -1
    LET zoom = def_zoom
    LET map_url = build_map_url(type,cnum,-1)
    IF map_url IS NULL THEN
       RETURN
    END IF

    OPEN WINDOW w_map WITH FORM "contmap"
    INPUT BY NAME map_url WITHOUT DEFAULTS
          ATTRIBUTES(UNBUFFERED, ACCEPT=FALSE)
        --ON CHANGE map_url DISPLAY map_url
        ON ACTION zoom_in
           IF zoom <= max_zoom THEN
              LET zoom=zoom+1
              LET map_url = build_map_url(type,cnum,zoom)
           END IF
        ON ACTION zoom_out
           IF zoom >= min_zoom THEN
              LET zoom=zoom-1
              LET map_url = build_map_url(type,cnum,zoom)
           END IF
        ON ACTION find
           MENU %"contmap.find.title" ATTRIBUTES(STYLE="popup")
               COMMAND %"contmap.find.all"
                 LET type = "A"
                 LET cnum = -1
                 LET zoom = def_zoom
                 LET map_url = build_map_url(type,cnum,-1)
                 EXIT MENU
               COMMAND %"contmap.find.single"
                 LET cnum = contact_lookup_list(cnum)
                 IF cnum IS NOT NULL THEN
                    LET type = "C"
                    LET zoom = def_zoom
                    LET map_url = build_map_url(type,cnum,-1)
                    EXIT MENU
                 END IF
               COMMAND %"contmap.find.myself"
                 LET type = "X"
                 LET cnum = -1
                 LET zoom = def_zoom
                 LET map_url = build_map_url(type,cnum,zoom)
                 EXIT MENU
               ON ACTION cancel
                 EXIT MENU
           END MENU
    END INPUT
    CLOSE WINDOW w_map

END FUNCTION

PRIVATE FUNCTION contact_lookup_list(cnum)
    DEFINE cnum INTEGER
    DEFINE arr DYNAMIC ARRAY OF RECORD
               num INTEGER,
               name STRING,
               desc STRING
           END RECORD,
           i, i2, x, u INTEGER
    LET u = contact_lookup_for_user(parameters.user_id)
    LET i2 = 0
    FOR i=1 TO contlist.getLength()
        IF i!=u AND NOT dbsync_marked_for_garbage(contlist[i].contact_rec_mstat) THEN
           LET i2=i2+1
           LET arr[i2].num = contlist[i].contact_num
           LET arr[i2].name = contlist[i].contact_name
           LET arr[i2].desc = contlist[i].short_desc
        END IF
    END FOR
    OPEN WINDOW w_lookup WITH FORM "list1"
    LET x = NULL
    DISPLAY ARRAY arr TO sr.* ATTRIBUTES(UNBUFFERED, ACCEPT=FALSE, DOUBLECLICK=SELECT)
        BEFORE DISPLAY
           LET i = contact_lookup_for_num(cnum)
           CALL DIALOG.setCurrentRow("sr",i)
        ON ACTION select
           LET x = contlist[DIALOG.getCurrentRow("sr")].contact_num
           ACCEPT DISPLAY
    END DISPLAY
    LET int_flag=FALSE
    CLOSE WINDOW w_lookup
    RETURN x
END FUNCTION

PRIVATE FUNCTION build_map_url(type,cnum,zoom)
    DEFINE type CHAR(1), cnum, zoom INTEGER
    DEFINE url, base, m_user, m_all, m_curr STRING,
           tmp, size STRING,
           x_lat, x_lon DECIMAL(10,6),
           lat, lon DECIMAL(10,6),
           x, i INTEGER

    WHENEVER ERROR CONTINUE
    CALL ui.Interface.frontCall("standard", "feinfo", ["screenresolution"], [size])
    WHENEVER ERROR STOP
    IF length(size)=0 THEN
       LET size = "400x400"
    END IF

    LET x = contact_lookup_for_user(parameters.user_id)
    IF x==0 THEN RETURN NULL END IF
    LET x_lat = contlist[x].contact_loc_lat
    LET x_lon = contlist[x].contact_loc_lon
    IF x_lat IS NULL THEN
       MESSAGE "NO GEOLOCALIZATION FOR CURRENT USER"
       RETURN NULL
    END IF
    LET m_user = SFMT("&markers=color:red%%7C%1,%2",x_lat,x_lon)

    IF zoom<0 THEN
       LET base = "https://maps.googleapis.com/maps/api/staticmap?&size=%1&maptype=roadmap"
    ELSE
       LET base = "https://maps.googleapis.com/maps/api/staticmap?&size=%1&center=%2,%3&zoom=%4&&maptype=roadmap"
    END IF

    IF type=="C" THEN
       LET x = contact_lookup_for_num(cnum)
       LET lat = contlist[x].contact_loc_lat
       LET lon = contlist[x].contact_loc_lon
       IF lat IS NOT NULL THEN
          LET m_curr = SFMT("&markers=color:green%%7Clabel:C%%7C%1,%2",lat,lon)
          LET url = SFMT(base, size, lat, lon, zoom) || m_curr
       ELSE
          MESSAGE "CURRENT CONTACT HAS NO LOCATION"
          RETURN NULL
       END IF
    ELSE -- A and X
       FOR i=1 TO contlist.getLength()
         IF i==x THEN CONTINUE FOR END IF
         LET lat= contlist[i].contact_loc_lat
         LET lon= contlist[i].contact_loc_lon
         IF lat IS NOT NULL THEN
            LET tmp = SFMT("&markers=color:blue%%7C%1,%2",lat,lon)
            IF m_all IS NULL THEN
               LET m_all = tmp
            ELSE
               LET m_all = m_all || tmp
            END IF
         END IF
       END FOR
       LET url = SFMT(base, size, x_lat, x_lon, zoom) || m_all
    END IF

--CALL mbox_ok( SFMT("Maps url: %1    %2", url, m_user) )
    RETURN url || m_user

END FUNCTION

PRIVATE FUNCTION get_short_desc(contact_num,mstat,city_num,city_desc)
    DEFINE contact_num INT, mstat CHAR(2), city_num INT, city_desc STRING
    DEFINE val STRING
    IF mstat != "S" THEN
       LET val = dbsync_mstat_desc(mstat)
    ELSE
       IF city_num != 1000 THEN
          LET val=city_desc
       END IF
    END IF
    RETURN SFMT("(%1) %2",contact_num, val)
END FUNCTION

PRIVATE FUNCTION load_contacts()
    DEFINE row INTEGER
    DEFINE tmp_byte BYTE
    CALL contlist.clear()
    CALL contlistattr.clear()
    DECLARE c_load_contacts CURSOR
        FOR SELECT
                contact.contact_num,
                contact.contact_rec_muser,
                contact.contact_rec_mtime,
                contact.contact_rec_mstat,
                contact.contact_name,
                contact.contact_valid,
                contact.contact_street,
                contact.contact_city,
                city.city_name||', '||city.city_country,
                contact.contact_num_m,
                contact.contact_num_w,
                contact.contact_num_h,
                contact.contact_user,
                contact.contact_loc_lon,
                contact.contact_loc_lat,
                contact.contact_photo
            FROM contact
                 LEFT OUTER JOIN city
                      ON ( city.city_num = contact.contact_city )
              ORDER BY contact.contact_name

    LOCATE tmp_byte IN MEMORY

    LET row = 1
    FOREACH c_load_contacts
            INTO
                contlist[row].contact_num,
                contlist[row].contact_rec_muser,
                contlist[row].contact_rec_mtime,
                contlist[row].contact_rec_mstat,
                contlist[row].contact_name,
                contlist[row].contact_valid,
                contlist[row].contact_street,
                contlist[row].contact_city,
                contlist[row].city_desc,
                contlist[row].contact_num_m,
                contlist[row].contact_num_w,
                contlist[row].contact_num_h,
                contlist[row].contact_user,
                contlist[row].contact_loc_lon,
                contlist[row].contact_loc_lat,
                tmp_byte

        IF contlist[row].city_desc IS NULL THEN
           LET contlist[row].city_desc = "<invalid city_num>"
        END IF
        LET contlist[row].short_desc = contlist[row].city_desc

        IF parameters.see_all OR
           (NOT dbsync_marked_for_deletion(contlist[row].contact_rec_mstat)) THEN

           LET contlist[row].short_desc =
               get_short_desc(contlist[row].contact_num,
                              contlist[row].contact_rec_mstat,
                              contlist[row].contact_city,
                              contlist[row].city_desc)

           LET contlistattr[row].short_desc = dbsync_mstat_color(contlist[row].contact_rec_mstat)

           IF length(tmp_byte) == 0 THEN
              LET contlist[row].contact_photo_file = ANONYMOUS_IMAGE_FILE
           ELSE
              LET contlist[row].contact_photo_file = byte_image_file_name(
                                                         contlist[row].contact_num,
                                                         contlist[row].contact_rec_mtime
                                                     )
              CALL tmp_byte.writeFile( contlist[row].contact_photo_file )
           END IF

           LET row = row + 1

        END IF
    END FOREACH
    CALL contlist.deleteElement(row)
    FREE c_load_contacts
END FUNCTION

PRIVATE FUNCTION get_aui_node(p, tagname, name)
    DEFINE p om.DomNode,
           tagname STRING,
           name STRING
    DEFINE nl om.NodeList
    IF name IS NOT NULL THEN
       LET nl = p.selectByPath(SFMT("//%1[@name=\"%2\"]",tagname,name))
    ELSE
       LET nl = p.selectByPath(SFMT("//%1",tagname))
    END IF
    IF nl.getLength() == 1 THEN
       RETURN nl.item(1)
    ELSE
       RETURN NULL
    END IF
END FUNCTION

PRIVATE FUNCTION add_style(pn, name)
    DEFINE pn om.DomNode,
           name STRING
    DEFINE nn om.DomNode
    LET nn = get_aui_node(pn, "Style", name)
    IF nn IS NOT NULL THEN RETURN NULL END IF
    LET nn = pn.createChild("Style")
    CALL nn.setAttribute("name", name)
    RETURN nn
END FUNCTION

PRIVATE FUNCTION set_style_attribute(pn, name, value)
    DEFINE pn om.DomNode,
           name STRING,
           value STRING
    DEFINE sa om.DomNode
    LET sa = get_aui_node(pn, "StyleAttribute", name)
    IF sa IS NULL THEN
       LET sa = pn.createChild("StyleAttribute")
       CALL sa.setAttribute("name", name)
    END IF
    CALL sa.setAttribute("value", value)
END FUNCTION

PRIVATE FUNCTION add_presentation_styles()
    DEFINE rn om.DomNode,
           sl om.DomNode,
           nn om.DomNode
    LET rn = ui.Interface.getRootNode()
    LET sl = get_aui_node(rn, "StyleList", NULL)
    --
    LET nn = add_style(sl, "Table.listview")
    IF nn IS NOT NULL THEN
       CALL set_style_attribute(nn, "tableType", "listView" )
    END IF
END FUNCTION
