# WARNING: Locale must be UTF-8!

IMPORT util
IMPORT com
IMPORT xml

IMPORT FGL libutil

SCHEMA contacts

TYPE t_geoloc_unit DECIMAL(10,6)
TYPE t_geoloc_position RECORD
           longitude t_geoloc_unit,
           latitude  t_geoloc_unit
     END RECORD

TYPE t_dbsync_event RECORD
           ident INTEGER ATTRIBUTE(XMLOPTIONAL),
           type STRING ATTRIBUTE(XMLOPTIONAL),
           data STRING ATTRIBUTE(XMLOPTIONAL)
       END RECORD

PUBLIC TYPE t_dbsync_event_array DYNAMIC ARRAY OF t_dbsync_event

PUBLIC TYPE t_selist RECORD
           command STRING,
           user_id t_user_id,
           user_auth t_user_auth ATTRIBUTE(XMLOPTIONAL), -- Encrypted!
           first_sync BOOLEAN,
           status STRING ATTRIBUTE(XMLOPTIONAL),
           elw RECORD ATTRIBUTE(XMLOptional) -- Record needed for XML serialization
               events t_dbsync_event_array
           END RECORD
       END RECORD

TYPE t_resinfo RECORD
           num INTEGER,
           info STRING
       END RECORD

TYPE t_creupd_info RECORD
           contact_num INTEGER,
           contact_loc_lon t_geoloc_unit,
           contact_loc_lat t_geoloc_unit
       END RECORD

TYPE t_numlistdet DYNAMIC ARRAY OF RECORD
           master_num INTEGER,
           detail_nums DYNAMIC ARRAY OF INTEGER
       END RECORD


PUBLIC DEFINE datafilter_city STRING

PRIVATE DEFINE google_api_key STRING,
               sync_url STRING,
               sync_format STRING,
               download_items DYNAMIC ARRAY OF RECORD
                                  type CHAR(2),
                                  num INTEGER
                              END RECORD,
               download_count INTEGER


PRIVATE FUNCTION add_event(events, type, data)
    DEFINE events t_dbsync_event_array, type, data STRING
    DEFINE x INTEGER
    LET x = events.getLength()+1
    LET events[x].ident = x
    LET events[x].type = type
    LET events[x].data = data
END FUNCTION

PRIVATE FUNCTION send_post_command(selist)
    DEFINE selist t_selist
    DEFINE selist_res t_selist,
           http_req com.HTTPRequest,
           http_resp com.HTTPResponse,
           d xml.DomDocument,
           n xml.DomNode,
           json STRING,
           err STRING

    IF sync_url IS NULL OR sync_format IS NULL THEN
       DISPLAY "send_post_command: Sync URL or format are not defined."
       EXIT PROGRAM 1
    END IF

    TRY
        IF sync_format=="xml" THEN
           LET d = xml.DomDocument.Create()
           LET n = d.createDocumentFragment()
           CALL xml.Serializer.VariableToDom(selist,n)
           CALL d.appendDocumentNode(n)
        ELSE
           LET json = util.JSON.stringify(selist)
        END IF
        LET http_req = com.HTTPRequest.Create(sync_url)
        CALL http_req.setConnectionTimeout(10)
        CALL http_req.setTimeout(60)
        CALL http_req.setMethod("POST")
        CALL http_req.setCharset("UTF-8")
        CALL http_req.setHeader("DBSync-Client","contact")
        CALL http_req.setHeader("Content-Encoding","gzip")
        IF sync_format=="xml" THEN
           CALL http_req.doXmlRequest(d)
        ELSE
           CALL http_req.doTextRequest(json)
        END IF
        LET http_resp=http_req.getResponse()
        IF http_resp.getStatusCode() != 200 THEN
           LET err = SFMT("(%1) : HTTP POST request status description: %2 ",
                          http_resp.getStatusCode(),
                          http_resp.getStatusDescription())
           INITIALIZE selist_res TO NULL
        ELSE
           IF sync_format=="xml" THEN
              LET d = http_resp.getXmlResponse()
              CALL xml.Serializer.DomToVariable(d.getDocumentElement(),selist_res)
           ELSE
              CALL util.JSON.parse(http_resp.getTextResponse(), selist_res)
           END IF
           LET err = NULL
        END IF
    CATCH
        LET err = SFMT("HTTP POST request error: STATUS=%1 (%2)",STATUS,SQLCA.SQLERRM)
        INITIALIZE selist_res TO NULL
    END TRY
    RETURN err, selist_res.*
END FUNCTION

PRIVATE FUNCTION send_get_request(command, query)
    DEFINE command, query STRING
    DEFINE selist_res t_selist,
           http_req com.HTTPRequest,
           http_resp com.HTTPResponse,
           d xml.DomDocument,
           uri, err STRING

    IF sync_url IS NULL OR sync_format IS NULL THEN
       DISPLAY "send_get_request: Sync URL or format are not defined."
       EXIT PROGRAM 1
    END IF

    LET uri = SFMT("%1/%2", sync_url, command)

    TRY
        LET http_req = com.HTTPRequest.Create(uri)
        CALL http_req.setConnectionTimeout(10)
        CALL http_req.setTimeout(60)
        CALL http_req.setMethod("GET")
        CALL http_req.setCharset("UTF-8")
        CALL http_req.setHeader("DBSync-Client","contact")
        CALL http_req.doFormEncodedRequest(query,FALSE)
        LET http_resp=http_req.getResponse()
        IF http_resp.getStatusCode() != 200 THEN
           LET err = SFMT("(%1) : HTTP GET request status description: %2 ",
                          http_resp.getStatusCode(),
                          http_resp.getStatusDescription())
           INITIALIZE selist_res TO NULL
        ELSE
           IF sync_format=="xml" THEN
              LET d = http_resp.getXmlResponse()
              CALL xml.Serializer.DomToVariable(d.getDocumentElement(),selist_res)
           ELSE
              CALL util.JSON.parse(http_resp.getTextResponse(), selist_res)
           END IF
           LET err = NULL
        END IF
    CATCH
        LET err = SFMT("HTTP GET request error: STATUS=%1 (%2)",STATUS,SQLCA.SQLERRM)
        INITIALIZE selist_res TO NULL
    END TRY
    RETURN err, selist_res.*
END FUNCTION

PRIVATE FUNCTION dbsync_result_desc(sync_status)
    DEFINE sync_status STRING
    CASE sync_status
       WHEN "user_invalid"
         RETURN -2, %"contacts.mess.cf.user_invalid"
       WHEN "user_invpswd"
         RETURN -3, %"contacts.mess.cf.user_password"
       WHEN "user_denied"
         RETURN -4, %"contacts.mess.cf.user_denied"
       WHEN "json_error"
         RETURN -11, %"contacts.mess.cf.json_error"
       WHEN "bind_user_failed"
         RETURN -21, %"contacts.mess.cf.bind_user_failed"
       WHEN "update_geoloc_failed"
         RETURN -31, %"contacts.mess.cf.update_geoloc_failed"
       WHEN "mtime_regist_failed"
         RETURN -41, %"contacts.mess.cf.mtime_regist_failed"
       WHEN "mtime_commit_failed"
         RETURN -42, %"contacts.mess.cf.mtime_commit_failed"
       WHEN "success"
         RETURN 0, NULL
       OTHERWISE
         RETURN -99, SFMT("ERROR: Unexpected result status: %1", sync_status)
    END CASE
END FUNCTION

PUBLIC FUNCTION dbsync_change_user_auth(user_id, old_auth, new_auth)
    DEFINE user_id t_user_id,
           old_auth t_user_auth, -- Encrypted
           new_auth t_user_auth  -- Encrypted
    DEFINE selist t_selist,
           s INT,
           result STRING,
           selist_res t_selist,
           desc STRING
    LET selist.command = "change_user_auth"
    LET selist.user_id = user_id
    LET selist.user_auth = old_auth
    LET selist.first_sync = FALSE
    LET selist.elw.events[1].data = new_auth
    CALL send_post_command(selist.*) RETURNING result, selist_res.*
    IF result IS NOT NULL THEN
       RETURN -1, SFMT("ERROR: status = %1",result)
    END IF
    CALL dbsync_result_desc(selist_res.status) RETURNING s, desc
    RETURN s, desc
END FUNCTION

PUBLIC FUNCTION dbsync_test_connection(user_id, user_auth)
    DEFINE user_id t_user_id,
           user_auth t_user_auth
    DEFINE selist t_selist,
           s INT,
           result STRING,
           selist_res t_selist,
           desc STRING
    LET selist.command = "test"
    LET selist.user_id = user_id
    LET selist.user_auth = user_auth
    LET selist.first_sync = FALSE
    CALL send_post_command(selist.*) RETURNING result, selist_res.*
    IF result IS NOT NULL THEN
       RETURN -1, SFMT("ERROR: status = %1",result)
    END IF
    CALL dbsync_result_desc(selist_res.status) RETURNING s, desc
    RETURN s, desc
END FUNCTION

PUBLIC FUNCTION dbsync_bind_user(user_id, user_auth, contact_num)
    DEFINE user_id t_user_id,
           user_auth t_user_auth,
           contact_num INTEGER
    DEFINE selist t_selist, s INT,
           result STRING,
           selist_res t_selist,
           desc STRING,
           old_cnum INT
    IF contact_num < 0 THEN
       RETURN -99, %"contacts.mess.bunew", 0
    END IF
    LET old_cnum = 0
    LET selist.command = "bind_user"
    LET selist.user_id = user_id
    LET selist.user_auth = user_auth
    LET selist.first_sync = FALSE
    LET selist.elw.events[1].ident = 1
    LET selist.elw.events[1].type = "set_user"
    LET selist.elw.events[1].data = contact_num
    CALL send_post_command(selist.*) RETURNING result, selist_res.*
    IF result IS NOT NULL THEN
       RETURN -1, SFMT("ERROR: status = %1",result), 0
    END IF
    CALL dbsync_result_desc(selist_res.status) RETURNING s, desc
    IF s==0 AND selist_res.elw.events.getLength()==1 THEN
       IF selist_res.elw.events[1].type = "old_cnum" THEN
          LET old_cnum = selist_res.elw.events[1].data
          UPDATE contact
             SET contact_user = v_undef,
                 contact_loc_lon = NULL,
                 contact_loc_lat = NULL
           WHERE contact_num = old_cnum
       END IF
    END IF
    RETURN s, desc, old_cnum
END FUNCTION

PRIVATE FUNCTION do_bind_user(uid, cnum, last_mtime, curr_mtime, events)
    DEFINE uid t_user_id,
           cnum INTEGER,
           last_mtime, curr_mtime DATETIME YEAR TO FRACTION(3),
           events t_dbsync_event_array
    DEFINE old_cnum INTEGER, status STRING
    LET status = "success"
    WHENEVER ERROR CONTINUE
    SELECT contact_num INTO old_cnum
      FROM contact WHERE contact_user = uid
    IF SQLCA.SQLCODE==0 THEN -- found
       IF old_cnum != cnum THEN
          -- Unbind uid from old contact 
          UPDATE contact
             SET contact_rec_mtime = curr_mtime,
                 contact_user = v_undef,
                 contact_loc_lon = NULL,
                 contact_loc_lat = NULL
           WHERE contact_num = old_cnum
           LET events[1].ident = 1
           LET events[1].type = "old_cnum"
           LET events[1].data = old_cnum
       ELSE
          LET cnum = 0 -- no need to reset uid for the same record...
       END IF
    END IF
    IF cnum > 0 THEN
       -- Bind uid to contact record identified by cnum
       UPDATE contact
          SET contact_rec_mtime = curr_mtime,
              contact_user = uid
        WHERE contact_num = cnum
          AND contact_rec_mtime <= last_mtime
          AND contact_user = v_undef -- Do not overwrite another user id!
       IF SQLCA.SQLCODE!=0 OR SQLCA.SQLERRD[3]!=1 THEN
          LET status = "bind_user_failed"
       END IF
    END IF
    WHENEVER ERROR STOP
    RETURN status
END FUNCTION

PRIVATE FUNCTION get_contact_geoloc(c_num, c_street, c_city, c_pos)
    DEFINE c_num LIKE contact.contact_num,
           c_street LIKE contact.contact_street,
           c_city LIKE contact.contact_city,
           c_pos t_geoloc_position
    DEFINE s INTEGER,
           c_city_name LIKE city.city_name,
           a_pos t_geoloc_position

    LET c_num = NULL -- Unused for now

    IF c_city==1000 THEN
       RETURN c_pos.*
    END IF
    SELECT city_name INTO c_city_name
           FROM city WHERE city_num = c_city
    IF c_street IS NULL THEN
       LET c_street = "center"
    END IF
    CALL geocod_find_coord(c_street,c_city_name) RETURNING s, a_pos.*
    IF s==0 THEN
       RETURN a_pos.*
    ELSE
       RETURN c_pos.*
    END IF

END FUNCTION

PUBLIC FUNCTION dbsync_update_geoloc(user_id, user_auth, lon, lat)
    DEFINE user_id t_user_id,
           user_auth t_user_auth,
           lon, lat t_geoloc_unit
    DEFINE selist t_selist, s INT,
           pos t_geoloc_position,
           result STRING,
           selist_res t_selist,
           desc STRING
    LET selist.command = "update_geoloc"
    LET selist.user_id = user_id
    LET selist.user_auth = user_auth
    LET selist.first_sync = FALSE
    LET selist.elw.events[1].ident = 1
    LET selist.elw.events[1].type = "position"
    LET pos.longitude = lon
    LET pos.latitude = lat
    LET selist.elw.events[1].data = util.JSON.stringify(pos)
    CALL send_post_command(selist.*) RETURNING result, selist_res.*
    IF result IS NOT NULL THEN
       RETURN -1, SFMT("ERROR: %1",result)
    END IF
    CALL dbsync_result_desc(selist_res.status) RETURNING s, desc
    IF s==0 THEN
       UPDATE contact
          SET contact_loc_lon = pos.longitude,
              contact_loc_lat = pos.latitude
        WHERE contact_user = user_id
    END IF
    RETURN s, desc
END FUNCTION

PRIVATE FUNCTION do_update_geoloc(uid, ps, curr_mtime)
    DEFINE uid t_user_id, ps STRING,
           curr_mtime DATETIME YEAR TO FRACTION(3)
    DEFINE pos t_geoloc_position, status STRING
    LET status = "success"
    CALL util.JSON.parse(ps, pos)
    WHENEVER ERROR CONTINUE
    UPDATE contact
       SET contact_rec_mtime = curr_mtime,  -- To have other users updated
           contact_loc_lon = pos.longitude,
           contact_loc_lat = pos.latitude
     WHERE contact_user = uid
    IF SQLCA.SQLCODE!=0 OR SQLCA.SQLERRD[3]!=1 THEN
       LET status = "update_geoloc_failed"
    END IF
    WHENEVER ERROR STOP
    RETURN status
END FUNCTION

PUBLIC FUNCTION dbsync_sync_contacts_send(first_sync, user_id, user_auth)
    DEFINE first_sync BOOLEAN,
           user_id t_user_id,
           user_auth t_user_auth
    DEFINE selist, selist_res t_selist,
           result, desc STRING,
           s INT
    LET selist.command = "mobile_changes"
    LET selist.user_id = user_id
    LET selist.user_auth = user_auth
    LET selist.first_sync = first_sync
    TRY
       CALL sync_contacts_collect_changes(user_id, selist.elw.events)
       CALL send_post_command(selist.*) RETURNING result, selist_res.*
       IF result IS NOT NULL THEN
          RETURN -2, result
       ELSE
          CALL sync_contacts_apply_results(user_id, selist_res.*) RETURNING s, desc
          IF s!=0 THEN
             RETURN s, desc
          END IF
          RETURN s, desc
       END IF
    CATCH
       RETURN -3, result
    END TRY
    RETURN 0, NULL
END FUNCTION

PUBLIC FUNCTION dbsync_get_download_count()
    RETURN download_items.getLength()
END FUNCTION

PUBLIC FUNCTION dbsync_sync_contacts_download(first_sync, user_id, user_auth, step_count)
    DEFINE first_sync BOOLEAN,
           user_id t_user_id,
           user_auth t_user_auth,
           step_count INTEGER
    DEFINE r, i, x, mode INTEGER,
           r_contact RECORD LIKE contact.*,
           r_contnote RECORD LIKE contnote.*,
           selist_res t_selist,
           result, query STRING

    LET first_sync = FALSE -- Unused for now

    LET r = 0

    IF download_count == download_items.getLength() THEN
       RETURN 1, NULL -- Done!
    END IF

    IF download_count == 0 THEN
       -- Cleanup SQLite DB trash
       EXECUTE IMMEDIATE "VACUUM"
       EXECUTE IMMEDIATE "PRAGMA foreign_key=ON"
    END IF

    IF step_count==-1 THEN
       LET step_count = download_items.getLength()
    END IF

    LOCATE r_contact.contact_photo IN MEMORY

    BEGIN WORK -- TODO: Handle SQL errors / rollback

    FOR i=1 TO step_count

        LET x = download_count + i
        IF x > download_items.getLength() THEN
           LET r = 1
           EXIT FOR
        END IF

        LET query = SFMT("user_id=%1&num=%2", user_id, download_items[x].num)
        IF user_auth IS NOT NULL THEN
           LET query = query, SFMT("&user_auth=%1", user_auth)
        END IF

        IF download_items[x].type == "C1" 
        OR download_items[x].type == "C2" THEN

           LET mode = IIF(download_items[x].type=="C1",1,2)
           CALL send_get_request(SFMT("get_contact_%1",mode), query)
                RETURNING result, selist_res.*
           IF result IS NOT NULL THEN
              LET r=-2
              GOTO download_fail
           END IF
           CASE selist_res.status
             WHEN "success"
               TRY
                  CALL util.JSON.parse(selist_res.elw.events[1].data, r_contact)
                  CALL refresh_contact(mode, r_contact.*)
               CATCH
                  LET r=-3
                  GOTO download_fail
               END TRY
             WHEN "contact_notfound" -- Record has been deleted since POST
               CALL dbsynclog_record(selist_res.status,"contact",download_items[x].num,NULL)
             WHEN "sql_error"
                  LET r=-4
                  GOTO download_fail
             OTHERWISE -- Cannot happen
                  LET r=-5
                  GOTO download_fail
           END CASE

        ELSE -- "NT"

           CALL send_get_request("get_contnote",query)
                RETURNING result, selist_res.*
           IF result IS NOT NULL THEN
              LET r=-2
              GOTO download_fail
           END IF
           CASE selist_res.status
             WHEN "success"
               TRY
                  CALL util.JSON.parse(selist_res.elw.events[1].data, r_contnote)
                  CALL refresh_contnote(r_contnote.*)
               CATCH
                  LET r=-3
                  GOTO download_fail
               END TRY
             WHEN "contnote_notfound" -- Record has been deleted since POST
               CALL dbsynclog_record(selist_res.status,"contnote",download_items[x].num,NULL)
             WHEN "sql_error"
                  LET r=-4
                  GOTO download_fail
             OTHERWISE -- Cannot happen
                  LET r=-5
                  GOTO download_fail
           END CASE

        END IF

    END FOR

    LET download_count = download_count + step_count

    COMMIT WORK
    RETURN r, result

LABEL download_fail:
    ROLLBACK WORK
    RETURN r, result

END FUNCTION

PUBLIC FUNCTION dbsync_send_return_receipt(user_id, user_auth)
    DEFINE user_id t_user_id,
           user_auth t_user_auth
    DEFINE result STRING,
           selist t_selist,
           selist_res t_selist
    LET selist.command = "return_receipt"
    LET selist.user_id = user_id
    LET selist.user_auth = user_auth
    LET selist.first_sync = FALSE
    CALL send_post_command(selist.*) RETURNING result, selist_res.*
    IF result IS NOT NULL THEN
       RETURN -1, result
    END IF
    RETURN 0, NULL
END FUNCTION

PRIVATE FUNCTION sync_contacts_collect_changes(user_id, events)
    DEFINE user_id t_user_id, events t_dbsync_event_array
    DEFINE r_contact, r_contact_2 RECORD LIKE contact.*, dummy_byte BYTE,
           r_contnote RECORD LIKE contnote.*

    LOCATE r_contact.contact_photo IN MEMORY
    LOCATE dummy_byte IN MEMORY

    CALL events.clear()

    -- contact table
    DECLARE m_contact CURSOR FOR
       SELECT * FROM contact
        WHERE contact_rec_muser = user_id
          AND contact_rec_mstat != "S"
        ORDER BY contact_rec_mtime -- Ordering by modification time!
    FOREACH m_contact INTO r_contact.*
        CASE
        WHEN dbsync_marked_for_deletion(r_contact.contact_rec_mstat)
            CALL add_event(events, "delete_contact",
                                   SFMT('{"contact_num":%1, "contact_name":"%2"}',
                                          r_contact.contact_num, r_contact.contact_name) )
        WHEN r_contact.contact_rec_mstat == "N"
            CALL add_event(events, "create_contact", util.JSON.stringify(r_contact) )
        WHEN r_contact.contact_rec_mstat == "U1"
            CALL add_event(events, "update_contact_1", util.JSON.stringify(r_contact) )
        WHEN r_contact.contact_rec_mstat == "U2"
            -- Do not include the photo for the JSON record, to avoid transfert
            LET r_contact_2.* = r_contact.*
            LET r_contact_2.contact_photo = dummy_byte
            CALL add_event(events, "update_contact_2", util.JSON.stringify(r_contact_2) )
        END CASE
    END FOREACH
    FREE m_contact

    -- contnote table:
    -- * Notes update is handled independently from contact master table
    -- * Must exclude notes of contact records marked for deletion
    DECLARE m_contnote CURSOR FOR
       SELECT contnote.*, contact_rec_mstat FROM contnote, contact
        WHERE contnote_rec_muser = user_id
          AND contnote_rec_mstat != "S"
          AND contnote_contact = contact_num
        ORDER BY contnote_rec_mtime -- Ordering by modification time!
    FOREACH m_contnote INTO r_contnote.*, r_contact.contact_rec_mstat
        IF NOT dbsync_marked_for_deletion(r_contact.contact_rec_mstat) THEN
          CASE
          WHEN r_contnote.contnote_rec_mstat == "D" -- No T1 / T2 case like in contact
            CALL add_event(events, "delete_contnote",
                                   SFMT('{"contnote_num":%1}', r_contnote.contnote_num) )
          WHEN r_contnote.contnote_rec_mstat == "N"
            CALL add_event(events, "create_contnote", util.JSON.stringify(r_contnote) )
          WHEN r_contnote.contnote_rec_mstat == "U"
            CALL add_event(events, "update_contnote", util.JSON.stringify(r_contnote) )
          END CASE
        END IF
    END FOREACH
    FREE m_contnote

END FUNCTION

PRIVATE FUNCTION sync_server_log(msg)
    DEFINE msg STRING
    DISPLAY SFMT("SYNC SERVER / %1: %2", CURRENT, msg)
END FUNCTION

PUBLIC FUNCTION dbsync_contacts_sync_server(selist_mod)
    DEFINE selist_mod t_selist
    DEFINE selist_res t_selist,
           last_user_mtime DATETIME YEAR TO FRACTION(3),
           curr_user_mtime DATETIME YEAR TO FRACTION(3),
           updlist_contact DYNAMIC ARRAY OF INTEGER,  -- Contacts updated by client, no refresh needed
           ffrlist_contact DYNAMIC ARRAY OF INTEGER,  -- Contacts with conflicts, for full refresh with photo
           updlist_contnote DYNAMIC ARRAY OF INTEGER, -- Contact notes updated by client, no refresh needed
           r SMALLINT

    IF selist_mod.command IS NULL THEN
       RETURN selist_res.*
    END IF

    LET selist_res.command = "result"
    LET selist_res.user_id = selist_mod.user_id
    LET selist_res.first_sync = selist_mod.first_sync

    -- Change password command
    IF selist_mod.command == "change_user_auth" THEN
       LET selist_res.status = libutil.users_change_auth(
                                  selist_mod.user_id,
                                  selist_mod.user_auth,     -- Encrypted
                                  selist_mod.elw.events[1].data -- Encrypted
                               )
       IF selist_res.status != "success" THEN
          CALL sync_server_log(SFMT("Password change failed for %1", selist_mod.user_id))
       ELSE
          CALL sync_server_log(SFMT("Password change succeeded for %1", selist_mod.user_id))
       END IF
       RETURN selist_res.*
    END IF

    -- Always test user validity...
    LET selist_res.status = libutil.users_check(selist_mod.user_id, selist_mod.user_auth)
    IF selist_res.status != "success" THEN
       CALL sync_server_log(SFMT("User authentication failed for %1", selist_mod.user_id))
       RETURN selist_res.*
    END IF

    -- Test command -> return success result
    IF selist_mod.command == "test" THEN
       CALL sync_server_log(SFMT("Test ok for user: %1", selist_mod.user_id))
       RETURN selist_res.*
    END IF

    CALL libutil.datafilter_get_last_mtime(selist_mod.user_id, "contact", selist_mod.first_sync)
         RETURNING last_user_mtime
    -- note1: Modification timestamp:
    --   o Must be UTC to avoid daylight saving time issues.
    --   o Must get current timestamp before starting processing requests, to
    --     take into account other users changes done during processing.
    --   o Will be saved temporarly, to let device GET data and confirm.
    --   o Once the device has got all updates, sends a return receipt to server
    --     which stores last moditification timestamp for next sync.
    --   o In case of problem, device does not send return receipt and next sync
    --     will restart at previous modification timestamp.
    --   WARNING! REST requests may be treated by different server processes,
    --   therefore we need to store temporary sync timestamp in the database!
    LET curr_user_mtime = util.Datetime.getCurrentAsUTC()

    -- Bind user command
    IF selist_mod.command == "bind_user" THEN
       -- See above, selist_res.status already set.
       CALL sync_server_log(SFMT("Binding user: %1 <= %2",
                                 selist_mod.user_id,
                                 selist_mod.elw.events[1].data))
       LET selist_res.status = do_bind_user(selist_mod.user_id,
                                            selist_mod.elw.events[1].data,
                                            last_user_mtime,
                                            curr_user_mtime,
                                            selist_res.elw.events)
       -- Personal data, no need to use sync timestamp.
       RETURN selist_res.*
    END IF

    -- Update geolocation command
    IF selist_mod.command == "update_geoloc" THEN
       CALL sync_server_log(SFMT("Update Geolocation for %1: %2",
                                 selist_mod.user_id,
                                 selist_mod.elw.events[1].data))
       -- See above, selist_res.status already set.
       LET selist_res.status = do_update_geoloc(selist_mod.user_id,
                                                selist_mod.elw.events[1].data,
                                                curr_user_mtime)
       -- Personal data, no need to use sync timestamp.
       RETURN selist_res.*
    END IF

    -- Changes from mobile databases
    IF selist_mod.command == "mobile_changes" THEN

       CALL sync_server_log(SFMT("Apply mobile changes for user %1:\n"
                              || "  Last mtime : %2\n"
                              || "  Curr mtime : %3",
                              selist_mod.user_id,
                              last_user_mtime,
                              curr_user_mtime))

       -- See above, selist_res.status already set.

       CALL do_mobile_changes(selist_mod.user_id,
                              selist_mod.elw.events,
                              last_user_mtime,
                              curr_user_mtime,
                              selist_res.elw.events,
                              updlist_contact,
                              ffrlist_contact,
                              updlist_contnote)

       CALL collect_central_changes(selist_mod.user_id,
                                    selist_res.elw.events,
                                    selist_mod.first_sync,
                                    last_user_mtime,
                                    updlist_contact,
                                    ffrlist_contact,
                                    updlist_contnote)

       -- Temporarly store modification timestamp until return receipt (note1)
       LET r = libutil.datafilter_register_mtime(selist_mod.user_id,"contact", curr_user_mtime)
       IF r < 0 THEN
          CALL sync_server_log(SFMT("Could not register temp timestamp for %1", selist_mod.user_id))
          LET selist_res.status = "mtime_regist_failed"
       END IF

       RETURN selist_res.*

    END IF

    -- Client return receipt
    IF selist_mod.command == "return_receipt" THEN
       CALL sync_server_log(SFMT("Return receipt got from %1", selist_mod.user_id))
       -- Store modification timestamp for next sync (note1)
       LET r = libutil.datafilter_commit_mtime(selist_mod.user_id,"contact")
       IF r < 0 THEN
          CALL sync_server_log(SFMT("Modification timestamp commit failed for %1", selist_mod.user_id))
          LET selist_res.status = "mtime_commit_failed"
       END IF
       RETURN selist_res.*
    END IF

    CALL sync_server_log(SFMT("Invalid command: %1", selist_mod.command))
    LET selist_res.status = "invalid_command"
    RETURN selist_res.*

END FUNCTION

PRIVATE FUNCTION parse_get_request_uri(uri)
    DEFINE uri STRING
    DEFINE x INTEGER,
           tok base.StringTokenizer,
           query, param STRING,
           user_id STRING,
           user_auth STRING,
           req_type STRING,
           obj_id INTEGER

    LET x = uri.getIndexOf("get_contact_1?user_id=",1)
    IF x>0 THEN
       LET x = x + LENGTH("get_contact_1?")
       LET query = uri.subString(x, uri.getLength())
       LET req_type = "get_contact_1"
    END IF
    LET x = uri.getIndexOf("get_contact_2?user_id=",1)
    IF x>0 THEN
       LET x = x + LENGTH("get_contact_2?")
       LET query = uri.subString(x, uri.getLength())
       LET req_type = "get_contact_2"
    END IF

    LET x = uri.getIndexOf("get_contnote?user_id=",1)
    IF x>0 THEN
       LET x = x + LENGTH("get_contnote?")
       LET query = uri.subString(x, uri.getLength())
       LET req_type = "get_contnote"
    END IF

    IF query IS NULL THEN
       RETURN NULL, NULL, NULL, NULL
    END IF

    LET tok = base.StringTokenizer.create(query,"&")
    WHILE tok.hasMoreTokens()
        LET param = tok.nextToken()
        CASE
        WHEN param MATCHES "user_id=*"
           LET x = param.getIndexOf("=",1)
           LET user_id = param.subString(x+1,param.getLength())
        WHEN param MATCHES "user_auth=*"
           LET x = param.getIndexOf("=",1)
           LET user_auth = param.subString(x+1,param.getLength())
        WHEN param MATCHES "num=*"
           LET x = param.getIndexOf("=",1)
           LET obj_id = param.subString(x+1,param.getLength())
        END CASE
    END WHILE

    RETURN user_id, user_auth, req_type, obj_id
END FUNCTION

PUBLIC FUNCTION dbsync_contacts_get_request(uri)
    DEFINE uri STRING
    DEFINE user_id STRING,
           user_auth STRING,
           req_type STRING,
           obj_id INTEGER,
           selist_res t_selist

    LET selist_res.command = "result"

    CALL parse_get_request_uri(uri)
         RETURNING user_id, user_auth, req_type, obj_id
    IF user_id IS NULL THEN
       LET selist_res.status = "invalid_uri"
       CALL sync_server_log(SFMT("Invalid URL: %1", uri))
       RETURN selist_res.*
    END IF

    LET selist_res.user_id = user_id
    LET selist_res.first_sync = FALSE

    -- Always test user validity...
    LET selist_res.status = libutil.users_check(user_id, user_auth)
    IF selist_res.status != "success" THEN
       CALL sync_server_log(SFMT("User authentication failed for %1", user_id))
       RETURN selist_res.*
    END IF

    -- Note: The record may have been deleted by another client since last POST

    CASE req_type
        WHEN "get_contact_1"
             CALL sync_server_log(SFMT("Query (full) contact record %1 for user %2", obj_id, user_id))
             LET selist_res.elw.events[1].type = "contact_record_1"
             CALL json_fetch_contact( 1, obj_id )
                  RETURNING selist_res.status, selist_res.elw.events[1].data
        WHEN "get_contact_2"
             CALL sync_server_log(SFMT("Query (short) contact record %1 for user %2", obj_id, user_id))
             LET selist_res.elw.events[1].type = "contact_record_2"
             CALL json_fetch_contact( 2, obj_id )
                  RETURNING selist_res.status, selist_res.elw.events[1].data
        WHEN "get_contnote"
             CALL sync_server_log(SFMT("Query contnote record %1 for user %2", obj_id, user_id))
             LET selist_res.elw.events[1].type = "contnote_record"
             CALL json_fetch_contnote( obj_id )
                  RETURNING selist_res.status, selist_res.elw.events[1].data
        OTHERWISE
             CALL sync_server_log(SFMT("Invalid GET command: %1", req_type))
    END CASE

    RETURN selist_res.*

END FUNCTION

PRIVATE FUNCTION json_fetch_contact(mode, num)
    DEFINE mode SMALLINT, num INTEGER
    DEFINE r_contact RECORD LIKE contact.*,
           sqlstat INTEGER
    CALL do_select_contact(mode, num) RETURNING sqlstat, r_contact.*
    CASE
      WHEN sqlstat==0
           RETURN "success", util.JSON.stringify(r_contact)
      WHEN sqlstat==NOTFOUND
           RETURN "contact_notfound", NULL
      OTHERWISE
           RETURN "sql_error", sqlstat
    END CASE
END FUNCTION

PRIVATE FUNCTION json_fetch_contnote(num)
    DEFINE num INTEGER
    DEFINE r_contnote RECORD LIKE contnote.*,
           sqlstat INTEGER
    SELECT contnote.* INTO r_contnote.* FROM contnote
           WHERE contnote_num = num
    LET sqlstat = SQLCA.SQLCODE
    CASE
      WHEN sqlstat==0
           RETURN "success", util.JSON.stringify(r_contnote)
      WHEN sqlstat==NOTFOUND
           RETURN "contnote_notfound", NULL
      OTHERWISE
           RETURN "sql_error", sqlstat
    END CASE
END FUNCTION

PRIVATE FUNCTION do_select_contact(mode, cnum)
    DEFINE mode SMALLINT,
           cnum INTEGER
    DEFINE r_contact RECORD LIKE contact.*,
           sqlstat INTEGER
    LET sqlstat = 0
    TRY
       IF mode==1 THEN
          LOCATE r_contact.contact_photo IN MEMORY
          SELECT contact.* INTO r_contact.*
             FROM contact
            WHERE contact_num = cnum
       ELSE
          SELECT
               contact_num,
               contact_rec_muser,
               contact_rec_mtime,
               contact_rec_mstat,
               contact_name,
               contact_valid,
               contact_street,
               contact_city,
               contact_num_m,
               contact_num_w,
               contact_num_h,
               contact_user,
               contact_loc_lon,
               contact_loc_lat
           INTO
               r_contact.contact_num,
               r_contact.contact_rec_muser,
               r_contact.contact_rec_mtime,
               r_contact.contact_rec_mstat,
               r_contact.contact_name,
               r_contact.contact_valid,
               r_contact.contact_street,
               r_contact.contact_city,
               r_contact.contact_num_m,
               r_contact.contact_num_w,
               r_contact.contact_num_h,
               r_contact.contact_user,
               r_contact.contact_loc_lon,
               r_contact.contact_loc_lat
             FROM contact
            WHERE contact_num = cnum
       END IF
       LET sqlstat = SQLCA.SQLCODE -- NOTFOUND does not raise error
    CATCH
       LET sqlstat = SQLCA.SQLCODE
    END TRY
    RETURN sqlstat, r_contact.*
END FUNCTION

PRIVATE FUNCTION do_update_contact(mode, r_contact)
    DEFINE mode SMALLINT,
           r_contact RECORD LIKE contact.*
    DEFINE r INTEGER,
           last_city INTEGER,
           photo_mtime DATETIME YEAR TO FRACTION(3)
    LET r = 0
    TRY
       SELECT contact_city, contact_photo_mtime
         INTO last_city, photo_mtime -- see1
         FROM contact
              WHERE contact_num = r_contact.contact_num
       UPDATE contact SET
           contact_rec_muser = r_contact.contact_rec_muser,
           contact_rec_mtime = r_contact.contact_rec_mtime,
           contact_rec_mstat = r_contact.contact_rec_mstat,
           contact_name      = r_contact.contact_name,
           contact_valid     = r_contact.contact_valid,
           contact_street    = r_contact.contact_street,
           contact_city      = r_contact.contact_city,
           contact_num_m     = r_contact.contact_num_m,
           contact_num_w     = r_contact.contact_num_w,
           contact_num_h     = r_contact.contact_num_h,
           contact_user      = r_contact.contact_user,
           contact_loc_lon   = r_contact.contact_loc_lon,
           contact_loc_lat   = r_contact.contact_loc_lat
        WHERE contact_num = r_contact.contact_num
       IF mode==1 THEN
          LET r_contact.contact_photo_mtime = r_contact.contact_rec_mtime
          UPDATE contact SET
                 contact_photo_mtime = r_contact.contact_photo_mtime,
                 contact_photo       = r_contact.contact_photo
           WHERE contact_num = r_contact.contact_num
       ELSE
          -- see1: If the city is changed, we force the photo update time
          -- even if the photo has not changed, so the next time users sync
          -- and city matches filter, the whole record will be fetched...
          IF r_contact.contact_city != last_city AND photo_mtime IS NOT NULL THEN
             LET r_contact.contact_photo_mtime = r_contact.contact_rec_mtime
             UPDATE contact SET
                    contact_photo_mtime = r_contact.contact_rec_mtime
              WHERE contact_num = r_contact.contact_num
          END IF
       END IF
    CATCH
       LET r = SQLCA.SQLCODE
    END TRY
    RETURN r
END FUNCTION

PRIVATE FUNCTION do_mobile_changes(uid,
                                   mod_events,
                                   last_mtime,
                                   curr_mtime,
                                   res_events,
                                   updlist_contact,
                                   ffrlist_contact,
                                   updlist_contnote)
    DEFINE uid t_user_id,
           mod_events t_dbsync_event_array,
           last_mtime DATETIME YEAR TO FRACTION(3),
           curr_mtime DATETIME YEAR TO FRACTION(3),
           res_events t_dbsync_event_array,
           updlist_contact DYNAMIC ARRAY OF INTEGER,
           ffrlist_contact DYNAMIC ARRAY OF INTEGER,
           updlist_contnote DYNAMIC ARRAY OF INTEGER
    DEFINE select_stmt STRING,
           r_contact RECORD LIKE contact.*,
           r_contnote RECORD LIKE contnote.*,
           resinfo t_resinfo,
           creupd_info t_creupd_info,
           r, i, num, negative_num, mode INTEGER,
           mres STRING,
           crelist_contact DYNAMIC ARRAY OF INTEGER,
           tmp_muser VARCHAR(50),
           tmp_mtime DATETIME YEAR TO FRACTION(3)

    LOCATE r_contact.contact_photo IN MEMORY

    LET select_stmt = "SELECT contact_rec_muser, contact_rec_mtime FROM contact WHERE contact_num = ?"
    IF fgl_db_driver_type() != "sqt" THEN
       LET select_stmt = select_stmt || " FOR UPDATE"
    END IF
    DECLARE c_update CURSOR FROM select_stmt

    FOR i=1 TO mod_events.getLength()

        CASE

        -- contact table

        WHEN mod_events[i].type == "delete_contact"
            TRY
               LET resinfo.num = 0
               CALL util.JSON.parse(mod_events[i].data, r_contact)
               LET r_contact.contact_rec_mtime = curr_mtime -- note1
               CALL sync_server_log(SFMT("Delete contact: %1",r_contact.contact_num))
               LET resinfo.num = r_contact.contact_num
               LET resinfo.info = r_contact.contact_name
               BEGIN WORK
               OPEN c_update USING r_contact.contact_num
               FETCH c_update INTO tmp_muser, tmp_mtime
               IF SQLCA.SQLCODE==NOTFOUND THEN
                  -- Phantom: The row does no more exist...
                  LET mres="delete_contact_phantom"
               ELSE
                  IF tmp_muser==uid -- Avoid conflicts with same user (geoloc updates)
                  OR tmp_mtime<=last_mtime THEN
                     DELETE FROM contnote
                            WHERE contnote_contact = r_contact.contact_num
                     DELETE FROM contact
                            WHERE contact_num = r_contact.contact_num
                     LET mres="delete_contact_success"
                  ELSE
                     -- Row updated by another user since last sync
                     LET mres="delete_contact_conflict"
                  END IF
               END IF
               CLOSE c_update
               COMMIT WORK
            CATCH
               LET mres="delete_contact_fail"
               IF resinfo.num == 0 THEN
                  LET resinfo.info="Delete data JSON parsing error"
               ELSE
                  LET resinfo.info=SQLERRMESSAGE
                  ROLLBACK WORK
               END IF
            END TRY
            CALL add_event(res_events, mres, util.JSON.stringify(resinfo))

        WHEN mod_events[i].type == "create_contact"
            TRY
               LET resinfo.num = 0
               CALL util.JSON.parse(mod_events[i].data, r_contact)
               LET r_contact.contact_rec_mtime = curr_mtime -- note1
               LET r_contact.contact_photo_mtime = r_contact.contact_rec_mtime
               CALL sync_server_log(SFMT("Create contact: %1",r_contact.contact_name))
               LET negative_num = r_contact.contact_num
               LET resinfo.num = r_contact.contact_num
               BEGIN WORK
               LET r_contact.contact_rec_mstat = "S"
               -- Assign a real primary key from sequence
               LET r_contact.contact_num = libutil.sequence_next("contact")
               IF r_contact.contact_num < 0 THEN
                  LET mres="create_contact_fail"
                  LET resinfo.info="Could not get new sequence for primary key"
                  ROLLBACK WORK
               ELSE
                  CALL get_contact_geoloc(
                         r_contact.contact_num,
                         r_contact.contact_street,
                         r_contact.contact_city,
                         r_contact.contact_loc_lon,
                         r_contact.contact_loc_lat
                       ) RETURNING r_contact.contact_loc_lon,
                                   r_contact.contact_loc_lat
                  INSERT INTO contact VALUES ( r_contact.* )
                  COMMIT WORK
                  LET mres="create_contact_success"
                  LET creupd_info.contact_num = r_contact.contact_num
                  LET creupd_info.contact_loc_lon = r_contact.contact_loc_lon
                  LET creupd_info.contact_loc_lat = r_contact.contact_loc_lat
                  LET resinfo.info = util.JSON.stringify(creupd_info)
                  LET crelist_contact[-negative_num] = r_contact.contact_num
                  LET updlist_contact[updlist_contact.getLength()+1] = r_contact.contact_num
               END IF
            CATCH
               LET mres="create_contact_fail"
               IF resinfo.num == 0 THEN
                  LET resinfo.info="Creation data JSON parsing error"
               ELSE
                  LET resinfo.info=SQLERRMESSAGE
                  ROLLBACK WORK
               END IF
            END TRY
            CALL add_event(res_events, mres, util.JSON.stringify(resinfo))

        WHEN mod_events[i].type == "update_contact_1"
          OR mod_events[i].type == "update_contact_2"
            TRY
               LET resinfo.num = 0
               CALL util.JSON.parse(mod_events[i].data, r_contact)
               LET r_contact.contact_rec_mtime = curr_mtime -- note1
               CALL sync_server_log(SFMT("Update contact: %1",r_contact.contact_num))
               LET resinfo.num = r_contact.contact_num
               LET resinfo.info = r_contact.contact_name
               BEGIN WORK
               -- Set exclusive lock and verify modification time
               UPDATE contact SET
                 contact_valid = r_contact.contact_valid
                WHERE contact_num = r_contact.contact_num
                  AND ( contact_rec_mtime <= last_mtime
                        OR contact_rec_muser = uid ) -- Avoid conflicts with same user (geoloc updates)
               IF SQLCA.SQLERRD[3]==1 THEN
                  -- Row found and not updated since last sync
                  LET r_contact.contact_rec_mstat = "S"
                  -- Get geo location according to address
                  CALL get_contact_geoloc(
                         r_contact.contact_num,
                         r_contact.contact_street,
                         r_contact.contact_city,
                         r_contact.contact_loc_lon,
                         r_contact.contact_loc_lat
                       ) RETURNING r_contact.contact_loc_lon,
                                   r_contact.contact_loc_lat
                  -- Set values for update_contact_1 or update_contact_2
                  LET mode = IIF(mod_events[i].type=="update_contact_1", 1, 2)
                  LET r = do_update_contact( mode, r_contact.* )
                  IF r < 0 THEN
                     LET mres="update_contact_fail"
                     LET resinfo.info=SQLERRMESSAGE
                     ROLLBACK WORK
                  ELSE
                     LET mres="update_contact_success"
                     LET creupd_info.contact_num = r_contact.contact_num
                     LET creupd_info.contact_loc_lon = r_contact.contact_loc_lon
                     LET creupd_info.contact_loc_lat = r_contact.contact_loc_lat
                     LET resinfo.info = util.JSON.stringify(creupd_info)
                     LET updlist_contact[updlist_contact.getLength()+1] = r_contact.contact_num
                  END IF
               ELSE
                  SELECT contact_num INTO num
                    FROM contact
                   WHERE contact_num = r_contact.contact_num
                  IF SQLCA.SQLCODE==NOTFOUND THEN
                     -- Phantom: The row does no more exist...
                     LET mres="update_contact_phantom"
                  ELSE
                     -- Row updated by another user since last sync
                     LET mres="update_contact_conflict"
                     LET ffrlist_contact[ffrlist_contact.getLength()+1] = r_contact.contact_num
                  END IF
               END IF
               COMMIT WORK
            CATCH
               LET mres="update_contact_fail"
               IF resinfo.num == 0 THEN
                  LET resinfo.info="Update data JSON parsing error"
               ELSE
                  LET resinfo.info=SQLERRMESSAGE
                  ROLLBACK WORK
               END IF
            END TRY
            CALL add_event(res_events, mres, util.JSON.stringify(resinfo))

        -- contnote table

        WHEN mod_events[i].type == "delete_contnote"
            TRY
               LET resinfo.num = 0
               CALL util.JSON.parse(mod_events[i].data, r_contnote)
               LET r_contnote.contnote_rec_mtime = curr_mtime -- note1
               CALL sync_server_log(SFMT("Delete contnote: %1",r_contnote.contnote_num))
               LET resinfo.num = r_contnote.contnote_num
               LET resinfo.info = r_contnote.contnote_when
               DELETE FROM contnote
                 WHERE contnote_num = r_contnote.contnote_num
                   AND contnote_rec_mtime <= last_mtime
               IF SQLCA.SQLERRD[3]==1 THEN
                  -- Row found and not updated since last sync
                  LET mres="delete_contnote_success"
               ELSE
                  SELECT contnote_num INTO num
                    FROM contnote
                   WHERE contnote_num = r_contnote.contnote_num
                  IF SQLCA.SQLCODE==NOTFOUND THEN
                     -- Phantom: The row does no more exist...
                     LET mres="delete_contnote_phantom"
                  ELSE
                     -- Row updated by another user since last sync
                     LET mres="delete_contnote_conflict"
                     LET ffrlist_contact[ffrlist_contact.getLength()+1] = r_contact.contact_num
                  END IF
               END IF
            CATCH
               LET mres="delete_contnote_fail"
               IF resinfo.num == 0 THEN
                  LET resinfo.info="Delete data JSON parsing error"
               ELSE
                  LET resinfo.info=SQLERRMESSAGE
               END IF
            END TRY
            CALL add_event(res_events, mres, util.JSON.stringify(resinfo))

        WHEN mod_events[i].type == "create_contnote"
            TRY
               LET resinfo.num = 0
               CALL util.JSON.parse(mod_events[i].data, r_contnote)
               LET r_contnote.contnote_rec_mtime = curr_mtime -- note1
               LET resinfo.num = r_contnote.contnote_num
               CALL sync_server_log(SFMT("Create contnote: %1",r_contnote.contnote_when))
               IF r_contnote.contnote_contact < 0 THEN
                  LET r_contnote.contnote_contact = crelist_contact[-r_contnote.contnote_contact]
               END IF
               BEGIN WORK
               -- Make sure contact master record still exists and lock it...
               OPEN c_update USING r_contnote.contnote_contact
               FETCH c_update INTO tmp_muser, tmp_mtime
               IF SQLCA.SQLCODE==NOTFOUND THEN
                  -- Phantom: The master record does no more exist...
                  LET mres="create_contnote_phantom_contact"
                  COMMIT WORK
               ELSE
                  LET r_contnote.contnote_rec_mstat = "S"
                  -- Assign a real primary key from sequence
                  LET r_contnote.contnote_num = libutil.sequence_next("contnote")
                  IF r_contnote.contnote_num < 0 THEN
                     LET mres="create_contnote_fail"
                     LET resinfo.info="Could not get new sequence for primary key"
                     CLOSE c_update
                     ROLLBACK WORK
                  ELSE
                     INSERT INTO contnote VALUES ( r_contnote.* )
                     CLOSE c_update
                     COMMIT WORK
                     LET mres="create_contnote_success"
                     LET resinfo.info = r_contnote.contnote_num -- Real pkey!
                     LET updlist_contnote[updlist_contnote.getLength()+1] = r_contnote.contnote_num
                  END IF
               END IF
            CATCH
               LET mres="create_contnote_fail"
               IF resinfo.num == 0 THEN
                  LET resinfo.info="Creation data JSON parsing error"
               ELSE
                  -- TODO:
                  -- If the reason is unique constraint error of (contnote_contact, contnote_when),
                  -- add a millisecond to contnote_when and try again to insert...
                  LET resinfo.info=SQLERRMESSAGE
                  ROLLBACK WORK
               END IF
            END TRY
            CALL add_event(res_events, mres, util.JSON.stringify(resinfo))

        WHEN mod_events[i].type MATCHES "update_contnote"
            TRY
               LET resinfo.num = 0
               CALL util.JSON.parse(mod_events[i].data, r_contnote)
               LET r_contnote.contnote_rec_mtime = curr_mtime -- note1
               LET r_contnote.contnote_rec_mstat = "S"
               CALL sync_server_log(SFMT("Update contnote: %1",r_contnote.contnote_num))
               LET resinfo.num = r_contnote.contnote_num
               LET resinfo.info = r_contnote.contnote_when
               BEGIN WORK
               -- Do not change contnote_when value: It's the creation timestamp.
               UPDATE contnote SET
                         contnote_rec_muser = r_contnote.contnote_rec_muser,
                         contnote_rec_mtime = r_contnote.contnote_rec_mtime,
                         contnote_rec_mstat = r_contnote.contnote_rec_mstat,
                         contnote_text = r_contnote.contnote_text
                WHERE contnote_num = r_contnote.contnote_num
                  AND contnote_rec_mtime <= last_mtime
               IF SQLCA.SQLERRD[3]==1 THEN
                  -- Row found and not updated since last sync
                  LET mres="update_contnote_success"
                  LET updlist_contnote[updlist_contnote.getLength()+1] = r_contnote.contnote_num
               ELSE
                  SELECT contnote_num INTO num
                    FROM contnote
                   WHERE contnote_num = r_contnote.contnote_num
                  IF SQLCA.SQLCODE==NOTFOUND THEN
                     -- Phantom: The row does no more exist...
                     LET mres="update_contnote_phantom"
                  ELSE
                     -- Row updated by another user since last sync
                     LET mres="update_contnote_conflict"
                  END IF
               END IF
               COMMIT WORK
            CATCH
               LET mres="update_contnote_fail"
               IF resinfo.num == 0 THEN
                  LET resinfo.info="Update data JSON parsing error"
               ELSE
                  LET resinfo.info=SQLERRMESSAGE
                  ROLLBACK WORK
               END IF
            END TRY
            CALL add_event(res_events, mres, util.JSON.stringify(resinfo))

        END CASE

    END FOR

END FUNCTION

PRIVATE FUNCTION collect_central_changes(uid,
                                         res_events,
                                         first_sync,
                                         last_mtime,
                                         updlist_contact,
                                         ffrlist_contact,
                                         updlist_contnote)
    DEFINE uid t_user_id,
           res_events t_dbsync_event_array,
           first_sync BOOLEAN,
           last_mtime DATETIME YEAR TO FRACTION(3),
           updlist_contact DYNAMIC ARRAY OF INTEGER,
           ffrlist_contact DYNAMIC ARRAY OF INTEGER,
           updlist_contnote DYNAMIC ARRAY OF INTEGER
    DEFINE no_refresh_list STRING,
           r_contact RECORD LIKE contact.*,
           r_contnote RECORD LIKE contnote.*,
           sqlcmd STRING,
           num, numdet INTEGER,
           i, x INTEGER,
           numlistdet t_numlistdet,
           wp_contact VARCHAR(250),
           wp_city VARCHAR(250),
           refresh_cmd STRING

    -- Find changes in the central database since last sync
    -- * Can ignore records that are filtered for this user
    -- * Must ignore records updated by applying change for this user
    -- * WHERE clause must include condition to get contact record bound to user_id
    CALL libutil.datafilter_get_filter(uid, "contact")
         RETURNING wp_contact
    IF wp_contact IS NOT NULL THEN
       LET wp_contact = "(", wp_contact, ") OR contact_user='", uid, "'"
    END IF

    -- contact table:
    LET no_refresh_list = libutil.intarr_to_list(updlist_contact)
    LET sqlcmd = "SELECT contact_num, contact_rec_mtime, contact_photo_mtime",
                 " FROM contact",
                 " WHERE contact_rec_mtime > ? ",
                 IIF(wp_contact IS NULL, " ", " AND ("||wp_contact||")"),
                 IIF(no_refresh_list IS NULL, " ", " AND contact_num NOT IN ("||no_refresh_list||")"),
                 " ORDER BY contact_rec_mtime" -- Important for unique names: (1)A->X, (2)B->A
    DECLARE c_contact CURSOR FROM sqlcmd
    INITIALIZE r_contact.* TO NULL -- We want only the contact_num
    FOREACH c_contact
            USING last_mtime
            INTO r_contact.contact_num,
                 r_contact.contact_rec_mtime,
                 r_contact.contact_photo_mtime
--display sfmt("Refresh contact %1: photo_mtime=%2  last_mtime=%3", r_contact.contact_num, r_contact.contact_photo_mtime, last_mtime)
        IF first_sync
        OR r_contact.contact_photo_mtime > last_mtime
        OR libutil.intarr_lookup(ffrlist_contact,r_contact.contact_num) THEN
           LET refresh_cmd = "refresh_contact_1"
        ELSE
           LET refresh_cmd = "refresh_contact_2"
        END IF
        LET r_contact.contact_rec_mtime = NULL
        LET r_contact.contact_photo_mtime = NULL
        CALL add_event(res_events, refresh_cmd, util.JSON.stringify(r_contact) )
        CALL sync_server_log(SFMT("Detected central change for contact %1\n  Update type: %2",
                                  r_contact.contact_num, refresh_cmd))
    END FOREACH
    FREE c_contact

    -- contnote table:
    LET no_refresh_list = libutil.intarr_to_list(updlist_contnote)
    LET sqlcmd = "SELECT contnote_num FROM contnote, contact",
                 " WHERE contnote_rec_mtime > ? ",
                 " AND contnote_contact = contact_num",
                 IIF(wp_contact IS NULL, " ", " AND ("||wp_contact||")"),
                 IIF(no_refresh_list IS NULL, " ", " AND contnote_num NOT IN ("||no_refresh_list||")"),
                 " ORDER BY contact_rec_mtime"
    DECLARE c_contnote CURSOR FROM sqlcmd
    INITIALIZE r_contnote.* TO NULL -- We want only the contnote_num
    FOREACH c_contnote USING last_mtime INTO r_contnote.contnote_num
        CALL add_event(res_events, "refresh_contnote", util.JSON.stringify(r_contnote) )
        CALL sync_server_log(SFMT("Detected central change for contnote %1",
                                  r_contnote.contnote_num))
    END FOREACH
    FREE c_contnote

    -- Create list of records selected for the user, to remove phantom records
    LET sqlcmd = "SELECT contact_num FROM contact",
                 IIF(wp_contact IS NULL, " ", " WHERE "||wp_contact)
    DECLARE c_contact_user CURSOR FROM sqlcmd
    DECLARE c_contnote_user CURSOR
            FOR SELECT contnote_num FROM contnote WHERE contnote_contact = ?
    CALL numlistdet.clear()
    FOREACH c_contact_user INTO num
       LET x = numlistdet.getLength()+1
       LET numlistdet[x].master_num = num
       LET i = 0
       FOREACH c_contnote_user USING num INTO numdet
          LET i = i+1
          LET numlistdet[x].detail_nums[i] = numdet
       END FOREACH
    END FOREACH
    FREE c_contact_user
    FREE c_contnote_user
    -- Warning: Always generate this result event even with en empty list, to
    -- trigger the code on mobile and remove delete records
    CALL add_event(res_events, "filter_contact", util.JSON.stringify(numlistdet) )

    -- Define datafilter where part for table city
    CALL libutil.datafilter_get_filter(uid, "city")
         RETURNING wp_city
    IF wp_city IS NOT NULL THEN
       CALL add_event(res_events, "datafilter_city", wp_city)
    END IF

END FUNCTION

PRIVATE FUNCTION sync_contacts_apply_results(user_id, selist_res)
    DEFINE user_id t_user_id,
           selist_res t_selist
    DEFINE r_contact RECORD LIKE contact.*,
           r_contnote RECORD LIKE contnote.*,
           resinfo t_resinfo,
           numlistdet t_numlistdet,
           i, x, s INTEGER, desc STRING

    LET user_id = NULL -- Unused for now

    IF selist_res.command IS NULL THEN
       RETURN 0, NULL
    END IF
    LET download_count = 0
    CALL dbsynclog_clear()
    CALL download_items.clear()
    IF selist_res.status != "success" THEN
       CALL dbsync_result_desc(selist_res.status) RETURNING s, desc
       RETURN s, desc
    END IF
    BEGIN WORK -- TODO: Handle SQL errors / rollback
    FOR i=1 TO selist_res.elw.events.getLength()
        CASE selist_res.elw.events[i].type
            -- contact table:
            WHEN "delete_contact_success"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               DELETE FROM contnote WHERE contnote_contact = resinfo.num
               DELETE FROM contact WHERE contact_num = resinfo.num
            WHEN "delete_contact_phantom"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               DELETE FROM contnote WHERE contnote_contact = resinfo.num
               DELETE FROM contact WHERE contact_num = resinfo.num
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contact",resinfo.num,resinfo.info)
            WHEN "delete_contact_fail"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contact(resinfo.num,"R",resinfo.info)
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contact",resinfo.num,resinfo.info)
            WHEN "delete_contact_conflict"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contact(resinfo.num,"E",resinfo.info)
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contact",resinfo.num,resinfo.info)
            WHEN "create_contact_success"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contact(resinfo.num,"s",resinfo.info)
            WHEN "create_contact_fail"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contact(resinfo.num,"C",resinfo.info)
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contact",resinfo.num,resinfo.info)
            WHEN "update_contact_success"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contact(resinfo.num,"S",resinfo.info)
            WHEN "update_contact_phantom"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contact(resinfo.num,"P",resinfo.info)
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contact",resinfo.num,resinfo.info)
            WHEN "update_contact_fail"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contact(resinfo.num,"X",resinfo.info)
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contact",resinfo.num,resinfo.info)
            WHEN "update_contact_conflict"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contact(resinfo.num,"M",resinfo.info)
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contact",resinfo.num,resinfo.info)
            WHEN "refresh_contact_1" -- With photo data 
               CALL util.JSON.parse(selist_res.elw.events[i].data, r_contact)
               LET x = download_items.getLength()+1
               LET download_items[x].type = "C1"
               LET download_items[x].num = r_contact.contact_num
            WHEN "refresh_contact_2" -- Without photo data 
               CALL util.JSON.parse(selist_res.elw.events[i].data, r_contact)
               LET x = download_items.getLength()+1
               LET download_items[x].type = "C2"
               LET download_items[x].num = r_contact.contact_num
            WHEN "filter_contact"
               CALL util.JSON.parse(selist_res.elw.events[i].data, numlistdet)
               CALL filter_contact(numlistdet)
            -- contnote table:
            WHEN "delete_contnote_success"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               DELETE FROM contnote WHERE contnote_num = resinfo.num
            WHEN "delete_contnote_phantom"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               DELETE FROM contnote WHERE contnote_num = resinfo.num
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contnote",resinfo.num,resinfo.info)
            WHEN "delete_contnote_fail"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contnote(resinfo.num,"R",resinfo.info)
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contnote",resinfo.num,resinfo.info)
            WHEN "delete_contnote_conflict"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contnote(resinfo.num,"E",resinfo.info)
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contnote",resinfo.num,resinfo.info)
            WHEN "create_contnote_success"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contnote(resinfo.num,"s",resinfo.info)
            WHEN "create_contnote_phantom_contact"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contnote(resinfo.num,"C",resinfo.info)
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contnote",resinfo.num,resinfo.info)
            WHEN "create_contnote_fail"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contnote(resinfo.num,"C",resinfo.info)
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contnote",resinfo.num,resinfo.info)
            WHEN "update_contnote_success"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contnote(resinfo.num,"S",resinfo.info)
            WHEN "update_contnote_phantom"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contnote(resinfo.num,"P",resinfo.info)
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contnote",resinfo.num,resinfo.info)
            WHEN "update_contnote_fail"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contnote(resinfo.num,"X",resinfo.info)
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contnote",resinfo.num,resinfo.info)
            WHEN "update_contnote_conflict"
               CALL util.JSON.parse(selist_res.elw.events[i].data, resinfo)
               CALL mark_contnote(resinfo.num,"M",resinfo.info)
               CALL dbsynclog_record(selist_res.elw.events[i].type,"contnote",resinfo.num,resinfo.info)
            WHEN "refresh_contnote"
               CALL util.JSON.parse(selist_res.elw.events[i].data, r_contnote)
               LET x = download_items.getLength()+1
               LET download_items[x].type = "NT"
               LET download_items[x].num = r_contnote.contnote_num
               
            -- General
            WHEN "datafilter_city"
               LET datafilter_city = selist_res.elw.events[i].data
        END CASE
    END FOR
    COMMIT WORK
    RETURN 0, NULL
END FUNCTION

PRIVATE FUNCTION refresh_contact(mode, r_contact)
    DEFINE mode SMALLINT,
           r_contact RECORD LIKE contact.*
    DEFINE x, r INTEGER
    SELECT contact_num INTO x
      FROM contact WHERE contact_num = r_contact.contact_num
    IF SQLCA.SQLCODE == 100 THEN
       INSERT INTO contact VALUES (r_contact.*)
    ELSE
       LET r = do_update_contact( mode, r_contact.* )
    END IF
END FUNCTION

PRIVATE FUNCTION refresh_contnote(rec)
    DEFINE rec RECORD LIKE contnote.*
    DEFINE x INTEGER
    SELECT contnote_num INTO x
      FROM contnote WHERE contnote_num = rec.contnote_num
    IF SQLCA.SQLCODE == 100 THEN
       INSERT INTO contnote VALUES (rec.*)
    ELSE
       UPDATE contnote SET contnote.* = rec.*
        WHERE contnote_num = rec.contnote_num
    END IF
END FUNCTION

PRIVATE FUNCTION filter_contact(numlistdet)
    DEFINE numlistdet t_numlistdet
    DEFINE i, x, num INTEGER, name VARCHAR(50), tmp STRING
    -- Delete contact records that are not in the filter list
    LET tmp = " NOT IN (-1"
    FOR i=1 TO numlistdet.getLength()
        LET tmp = tmp||","||numlistdet[i].master_num
    END FOR
    LET tmp = tmp||")"
    DECLARE c_filter_contact CURSOR FROM
      "SELECT contact_num, contact_name FROM contact"||
      " WHERE contact_rec_mstat='S' AND contact_num > 0 "||
      " AND contact_num "||tmp
    FOREACH c_filter_contact INTO num, name
        DELETE FROM contnote WHERE contnote_contact = num
        DELETE FROM contact WHERE contact_num = num
        CALL dbsynclog_record("filtered_or_deleted","contact",num,name)
    END FOREACH
    FREE c_filter_contact
    -- Delete contact note records that are not in the filter list
    LET tmp = " NOT IN (-1"
    FOR i=1 TO numlistdet.getLength()
        FOR x=1 TO numlistdet[i].detail_nums.getLength()
            LET tmp = tmp||","||numlistdet[i].detail_nums[x]
        END FOR
    END FOR
    LET tmp = tmp||")"
    EXECUTE IMMEDIATE "DELETE FROM contnote WHERE contnote_num " || tmp
END FUNCTION

PUBLIC FUNCTION dbsync_marked_for_deletion(mstat)
    DEFINE mstat STRING
    RETURN (mstat=="D" OR mstat=="T1" OR mstat=="T2")
END FUNCTION

PUBLIC FUNCTION dbsync_marked_for_garbage(mstat)
    DEFINE mstat STRING
    RETURN (mstat=="M" OR mstat=="E")
END FUNCTION

PUBLIC FUNCTION dbsync_marked_as_unsync(mstat)
    DEFINE mstat STRING
    RETURN (mstat=="C" OR mstat=="M" OR mstat=="X" OR mstat=="P" OR mstat=="E")
END FUNCTION

PRIVATE FUNCTION dbsync_mstat_info(mode,mstat)
    DEFINE mode, mstat STRING
    DEFINE val STRING
    CASE mstat
       WHEN "S"  LET val=IIF(mode=="D",%"contacts.mstatdesc.synchro",NULL)
       WHEN "N"  LET val=IIF(mode=="D",%"contacts.mstatdesc.created","green")
       WHEN "U"  LET val=IIF(mode=="D",%"contacts.mstatdesc.updated","blue")
       WHEN "U1" LET val=IIF(mode=="D",%"contacts.mstatdesc.updated","blue")
       WHEN "U2" LET val=IIF(mode=="D",%"contacts.mstatdesc.updated","blue")
       WHEN "D"  LET val=IIF(mode=="D",%"contacts.mstatdesc.deleted","cyan")
       WHEN "T1" LET val=IIF(mode=="D",%"contacts.mstatdesc.upd_del","red")
       WHEN "T2" LET val=IIF(mode=="D",%"contacts.mstatdesc.upd_del","red")
       WHEN "R"  LET val=IIF(mode=="D",%"contacts.mstatdesc.delfail","red")
       WHEN "E"  LET val=IIF(mode=="D",%"contacts.mstatdesc.delmiss","red")
       WHEN "C"  LET val=IIF(mode=="D",%"contacts.mstatdesc.addfail","red")
       WHEN "M"  LET val=IIF(mode=="D",%"contacts.mstatdesc.updmiss","red")
       WHEN "X"  LET val=IIF(mode=="D",%"contacts.mstatdesc.updfail","red")
       WHEN "P"  LET val=IIF(mode=="D",%"contacts.mstatdesc.phantom","magenta")
       OTHERWISE
          DISPLAY "dbsync_contacts: Unexpected modification status: ", mstat
          EXIT PROGRAM 1
    END CASE
    IF mode=="D" THEN
       LET val = val, " ("||mstat||")"
    END IF
    RETURN val
END FUNCTION

PUBLIC FUNCTION dbsync_mstat_desc(mstat)
    DEFINE mstat STRING
    RETURN dbsync_mstat_info("D",mstat)
END FUNCTION

PUBLIC FUNCTION dbsync_mstat_color(mstat)
    DEFINE mstat STRING
    RETURN dbsync_mstat_info("C",mstat)
END FUNCTION

PRIVATE FUNCTION update_contact_geoloc(num, creupd_info)
    DEFINE num INTEGER, creupd_info t_creupd_info
    DEFINE lon, lat t_geoloc_unit
    IF creupd_info.contact_loc_lon IS NOT NULL THEN
       LET lon = creupd_info.contact_loc_lon
       LET lat = creupd_info.contact_loc_lat
       UPDATE contact
          SET contact_loc_lon = lon,
              contact_loc_lat = lat
        WHERE contact_num = num
    END IF
END FUNCTION

PRIVATE FUNCTION new_unsync_name(name)
    DEFINE name STRING
    DEFINE x SMALLINT
    LET x = name.getIndexOf("(!",1)
    IF x > 1 THEN
       LET name = name.subString(1,x-1)
    END IF
    IF name.getLength()>25 THEN
       -- Make room for (!YYYY-MM-DD HH:MM:SS)
       LET name = name.subString(1,25)
    END IF
    RETURN name || SFMT("(!%1)",CURRENT YEAR TO SECOND)
END FUNCTION

PRIVATE FUNCTION mark_contact(num,flag,info)
    DEFINE num INTEGER, flag CHAR(2), info STRING
    DEFINE creupd_info t_creupd_info,
           curr_name, new_name VARCHAR(50),
           new_num INTEGER
    CASE
    WHEN dbsync_marked_as_unsync(flag)
       -- We do not want to lose entered data, so we must modify the record
       -- to avoid unique name conflicts, and maybe change the primary key
       -- because refreshes from server would overwrite the local changes.
       SELECT contact_num, contact_name
         INTO new_num, curr_name
         FROM contact
        WHERE contact_num = num
       IF flag != "P" THEN
          -- Change name to avoid unique constraint on contact_name + contact_city
          LET new_name = new_unsync_name(curr_name)
       ELSE
          LET new_name = curr_name
       END IF
       UPDATE contact
          SET contact_name = new_name,
              contact_rec_mstat = flag
        WHERE contact_num = num
       IF flag MATCHES "[ME]" THEN
          -- update/delete conflict: change primary key to make it local
          LET new_num = libutil.sequence_mobile_new("contact","contact_num")
          CALL change_contact_num(num, new_num, flag)
       END IF
    WHEN flag == "s"
       CALL util.JSON.parse(info, creupd_info)
       -- Newly created, nearly sync: needs new pkey from info
       CALL change_contact_num(num, creupd_info.contact_num, "S")
       -- Set geolocation found by server
       CALL update_contact_geoloc(num, creupd_info.*)
    WHEN flag == "S"
       -- Updated, nearly sync: may need geolocation update
       CALL util.JSON.parse(info, creupd_info)
       UPDATE contact
          SET contact_rec_mstat = flag
        WHERE contact_num = num
       -- Set geolocation found by server
       CALL update_contact_geoloc(num, creupd_info.*)
    OTHERWISE
       UPDATE contact
          SET contact_rec_mstat = flag
        WHERE contact_num = num
    END CASE
END FUNCTION

PRIVATE FUNCTION change_contact_num(old_num, new_num, new_flag)
    DEFINE old_num, new_num INTEGER, new_flag CHAR(2)
    DEFINE ct DATETIME YEAR TO FRACTION(3)
    -- Missing ON UPDATE CASCADE with Informix (SQLite / PostgreSQL only)!!!!
    -- Must create a temp contact to update the contnote detail...
    LET ct = CURRENT
    INSERT INTO contact (contact_num,
                         contact_rec_muser, contact_rec_mtime, contact_rec_mstat,
                         contact_name, contact_valid, contact_city,
                         contact_num_m, contact_num_w, contact_num_h,
                         contact_user)
                 VALUES (0,
                         '0', ct, '0',
                         '<temp>', 'N', 1000,
                         NULL, NULL, NULL,
                         v_undef )
    UPDATE contnote SET contnote_contact=0 WHERE contnote_contact=old_num
    UPDATE contact
       SET contact_num = new_num,
           contact_rec_mstat = new_flag
     WHERE contact_num = old_num
    UPDATE contnote SET contnote_contact=new_num WHERE contnote_contact=0
    DELETE FROM contact WHERE contact_num=0
END FUNCTION

PRIVATE FUNCTION mark_contnote(num,flag,info)
    DEFINE num INTEGER, flag CHAR(2), info STRING
    DEFINE new_num INTEGER
    CASE
    WHEN dbsync_marked_as_unsync(flag)
       -- In case of sync problem, we just remove the local note...
       DELETE FROM contnote WHERE contnote_num = num
    WHEN flag == "s" -- Newly created, nearly sync: needs new pkey from info
       LET new_num = info
       UPDATE contnote
          SET contnote_rec_mstat = "S",
              contnote_num = new_num
        WHERE contnote_num = num
    OTHERWISE
       UPDATE contnote
          SET contnote_rec_mstat = flag
        WHERE contnote_num = num
    END CASE
END FUNCTION

-- Delete phantom, delete and update conflict records
-- (this operation will be triggered by user on demand)
PUBLIC FUNCTION delete_garbage_contact()
    DEFINE num INTEGER
    BEGIN WORK
    DECLARE c_cleanup_contact CURSOR FOR
       SELECT contact_num
         FROM contact WHERE contact_rec_mstat IN ('P','M','E')
    FOREACH c_cleanup_contact INTO num
       DELETE FROM contnote WHERE contnote_contact = num
       DELETE FROM contact WHERE contact_num = num
    END FOREACH
    COMMIT WORK
    FREE c_cleanup_contact
END FUNCTION

-- Google Geocoding
-- The function finds the coordinates of the address passed.
-- Called when creating or updating a contact, to store coordinates and
-- geolocalize contact addresses on mobile devices.
-- We use a Google API key provided by the server program with -k option,
-- this key must be generated from google developer project.
-- See https://developers.google.com/maps/documentation/geocoding

FUNCTION dbsync_contacts_set_google_api_key(value)
    DEFINE value STRING
    LET google_api_key = value
END FUNCTION

FUNCTION dbsync_contacts_set_sync_url(value)
    DEFINE value STRING
    LET sync_url = value
END FUNCTION

FUNCTION dbsync_contacts_set_sync_format(value)
    DEFINE value STRING
    LET sync_format = value
END FUNCTION

PRIVATE FUNCTION replace_blank_to_plus(s)
    DEFINE s STRING
    DEFINE b base.StringBuffer
    LET b = base.StringBuffer.create()
    CALL b.append(s)
    CALL b.replace(" ","+",0)
    RETURN b.toString()
END FUNCTION

PRIVATE FUNCTION geocod_find_coord(address,city)
    DEFINE address, city STRING
    DEFINE position t_geoloc_position
    DEFINE s SMALLINT,
           query_uri STRING,
           http_req com.HTTPRequest,
           http_resp com.HTTPResponse,
           tmp, result STRING,
           j_response util.JSONObject,
           j_results util.JSONArray,
           j_first util.JSONObject,
           j_geometry util.JSONObject,
           j_location util.JSONObject

    IF google_api_key IS NULL THEN
       CALL sync_server_log("ERROR: no google_api_key provided...")
       RETURN -1, position.*
    END IF

    LET query_uri = SFMT(
        "https://maps.googleapis.com/maps/api/geocode/json?address=%1,%2&key=%3",
        replace_blank_to_plus(address),
        replace_blank_to_plus(city),
        google_api_key
        )

    TRY
        LET http_req = com.HTTPRequest.Create(query_uri)
        CALL http_req.setConnectionTimeout(5)
        CALL http_req.setTimeout(5)
        CALL http_req.doRequest()
        LET http_resp = http_req.getResponse()
        IF http_resp.getStatusCode() != 200 THEN
           --RETURN http_resp.getStatusCode(), http_resp.getStatusDescription()
           RETURN -2, position.*
        END IF
        LET tmp = http_resp.getStatusDescription()
        IF ( tmp == "OK" || tmp == "no error" ) THEN
           --RETURN -1, SFMT("HTTP request status description: %1 ",tmp)
           RETURN -3, position.*
        END IF
        LET result = http_resp.getTextResponse()
    CATCH
        --RETURN -2, SFMT("HTTP request error: STATUS=%1 (%2)",STATUS,SQLCA.SQLERRM)
        RETURN -4, position.*
    END TRY

    TRY
        LET j_response = util.JSONObject.parse(result)
        LET j_results = j_response.get("results")
        LET j_first = j_results.get(1)
        LET j_geometry = j_first.get("geometry")
        LET j_location = j_geometry.get("location")
        LET position.longitude = j_location.get("lng")
        LET position.latitude  = j_location.get("lat")
    CATCH
        RETURN -5, position.*
    END TRY

--display SFMT("Found coords : %1 = %2 / %3", query_uri, position.latitude, position.longitude)
    RETURN s, position.*

END FUNCTION

-- TODO: How to produce nice HTML?
FUNCTION dbsync_generate_status_text()
    DEFINE i, cnt INTEGER,
           res base.StringBuffer,
           contlist DYNAMIC ARRAY OF RECORD -- Uses CHAR to format.
                        contact_num LIKE contact.contact_num,
                        contact_rec_muser LIKE contact.contact_rec_muser,
                        contact_rec_mtime LIKE contact.contact_rec_mtime,
                        contact_rec_mstat LIKE contact.contact_rec_mstat,
                        contact_name CHAR(30),
                        city_name CHAR(20),
                        contact_user LIKE contact.contact_user,
                        contact_loc_lon LIKE contact.contact_loc_lon,
                        contact_loc_lat LIKE contact.contact_loc_lat,
                        contact_photo_mtime LIKE contact.contact_photo_mtime
                    END RECORD

    LET res = base.StringBuffer.create()

    DECLARE c_status_1 CURSOR FOR
            SELECT contact_num,
                   contact_rec_muser,
                   contact_rec_mtime,
                   contact_rec_mstat,
                   contact_name,
                   city_name,
                   contact_user,
                   contact_loc_lon,
                   contact_loc_lat,
                   contact_photo_mtime
              FROM contact, city
              WHERE contact_city = city_num
               ORDER BY contact_name

    LET cnt=1
    FOREACH c_status_1 INTO contlist[cnt].*
        LET cnt=cnt+1
    END FOREACH
    CALL contlist.deleteElement(cnt)
    LET cnt=cnt-1

    CALL res.append("WELCOME TO DBSYNC SERVER\n\n\n")
    CALL res.append(SFMT("List of contacts (%1)\n", cnt))
    FOR i=1 TO cnt
        CALL res.append(
             SFMT("\n%1 %2 %3                         %4\n",
                 contlist[i].contact_num,
                 contlist[i].contact_name,
                 contlist[i].city_name,
                 IIF((contlist[i].contact_user != "<undef>"),
                     SFMT("(bound to user %1)", contlist[i].contact_user),
                     NULL)
                 )
             )
        CALL res.append(
             SFMT("         Update info: muser=%1  mtime=%2  mstat=%3\n",
                 contlist[i].contact_rec_muser,
                 contlist[i].contact_rec_mtime,
                 contlist[i].contact_rec_mstat)
             )
        CALL res.append(
             SFMT("         Location: (%1/%2)   Photo mtime: %3\n", 
                 contlist[i].contact_loc_lon,
                 contlist[i].contact_loc_lat,
                 contlist[i].contact_photo_mtime)
             )
    END FOR

    RETURN res.toString()
END FUNCTION
