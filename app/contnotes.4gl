IMPORT util

IMPORT FGL libutil

SCHEMA contacts

PRIVATE DEFINE
   current_user t_user_id,
   current_contact INTEGER,
   when_cmb ui.ComboBox,
   curr_row INTEGER,
   is_new BOOLEAN,
   notelist DYNAMIC ARRAY OF RECORD LIKE contnote.*,
   rec RECORD
          contnote_num LIKE contnote.contnote_num,
          contnote_rec_muser LIKE contnote.contnote_rec_muser,
          contnote_rec_mtime LIKE contnote.contnote_rec_mtime,
          contnote_rec_mstat LIKE contnote.contnote_rec_mstat,
          contnote_when LIKE contnote.contnote_when,
          contnote_text LIKE contnote.contnote_text
       END RECORD

PRIVATE FUNCTION load_notes(contact_num)
    DEFINE contact_num INTEGER
    DEFINE x INTEGER
    DECLARE c_contnote CURSOR FOR
            SELECT * FROM contnote
             WHERE contnote_contact = contact_num
               AND contnote_rec_mstat NOT IN ('D')
             ORDER BY contnote_when
    LET x = 1
    CALL notelist.clear()
    FOREACH c_contnote INTO notelist[x].*
       LET x = x+1
    END FOREACH
    CALL notelist.deleteElement(x)
    IF notelist.getLength()==0 THEN
       CALL append_new_note()
    ELSE
       LET is_new = FALSE
    END IF
END FUNCTION

PRIVATE FUNCTION init_when_combobox()
    DEFINE x INTEGER
    LET when_cmb = ui.ComboBox.forName("contnote_when")
    FOR x=1 TO notelist.getLength()
       CALL when_cmb.addItem(notelist[x].contnote_when,notelist[x].contnote_when)
    END FOR
END FUNCTION

PRIVATE FUNCTION select_new_current()
    DEFINE x INTEGER
    FOR x=1 TO notelist.getLength()
        IF notelist[x].contnote_when == rec.contnote_when THEN
           LET curr_row = x
           EXIT FOR
        END IF
    END FOR
    CALL select_note(x)
END FUNCTION

PRIVATE FUNCTION select_note(x)
    DEFINE x INTEGER
    LET curr_row = x
    CALL notelist_to_rec()
    LET is_new = FALSE
END FUNCTION

PRIVATE FUNCTION remove_current_element()
    CALL when_cmb.removeItem(notelist[curr_row].contnote_when)
    CALL notelist.deleteElement(curr_row)
END FUNCTION

PRIVATE FUNCTION set_mrec_change(row, mstat)
    DEFINE row INTEGER, mstat CHAR(2)
    -- We set the mtime because it's not null in the DB.
    -- This value will be reset by server at sync time.
    LET notelist[row].contnote_rec_muser = current_user
    LET notelist[row].contnote_rec_mtime = util.Datetime.getCurrentAsUTC()
    LET notelist[row].contnote_rec_mstat = mstat
END FUNCTION

PRIVATE FUNCTION save_current_note()
    LET rec.contnote_text = rec.contnote_text CLIPPED
    IF ( rec.contnote_text == notelist[curr_row].contnote_text )
    OR ( rec.contnote_text IS NULL AND notelist[curr_row].contnote_text IS NULL )
    THEN
       RETURN
    END IF
    LET notelist[curr_row].contnote_text = rec.contnote_text
    IF is_new THEN
       IF LENGTH(rec.contnote_text CLIPPED) > 0 THEN
          CALL set_mrec_change(curr_row,"N")
          INSERT INTO contnote (
             contnote_num,
             contnote_rec_muser,
             contnote_rec_mtime,
             contnote_rec_mstat,
             contnote_contact,
             contnote_when,
             contnote_text
          ) VALUES (
             notelist[curr_row].contnote_num,
             notelist[curr_row].contnote_rec_muser,
             notelist[curr_row].contnote_rec_mtime,
             notelist[curr_row].contnote_rec_mstat,
             notelist[curr_row].contnote_contact,
             notelist[curr_row].contnote_when,
             notelist[curr_row].contnote_text
          )
       ELSE
          CALL remove_current_element()
       END IF
       LET is_new = FALSE
    ELSE
       IF LENGTH(rec.contnote_text CLIPPED) > 0 THEN
          IF notelist[curr_row].contnote_rec_mstat != "N" THEN
             CALL set_mrec_change(curr_row,"U")
          END IF
          UPDATE contnote
             SET contnote_rec_muser = notelist[curr_row].contnote_rec_muser,
                 contnote_rec_mtime = notelist[curr_row].contnote_rec_mtime,
                 contnote_rec_mstat = notelist[curr_row].contnote_rec_mstat,
                 contnote_text = notelist[curr_row].contnote_text
           WHERE contnote_num = notelist[curr_row].contnote_num
       ELSE -- Empty text = remove
          CALL delete_current_note()
       END IF
    END IF
END FUNCTION

PRIVATE FUNCTION notelist_to_rec()
    LET rec.contnote_num = notelist[curr_row].contnote_num
    LET rec.contnote_rec_muser = notelist[curr_row].contnote_rec_muser
    LET rec.contnote_rec_mtime = notelist[curr_row].contnote_rec_mtime
    LET rec.contnote_rec_mstat = notelist[curr_row].contnote_rec_mstat
    LET rec.contnote_when = notelist[curr_row].contnote_when
    LET rec.contnote_text = notelist[curr_row].contnote_text
END FUNCTION

PRIVATE FUNCTION rec_to_notelist()
    LET notelist[curr_row].contnote_when = rec.contnote_when
    LET notelist[curr_row].contnote_text = rec.contnote_text
END FUNCTION

PRIVATE FUNCTION append_new_note()
    LET curr_row = notelist.getLength()+1
    LET notelist[curr_row].contnote_num = libutil.sequence_mobile_new("contnote","contnote_num")
    LET notelist[curr_row].contnote_contact = current_contact
    CALL set_mrec_change(curr_row,"N")
    LET notelist[curr_row].contnote_when = CURRENT
    LET notelist[curr_row].contnote_text = NULL
    CALL notelist_to_rec()
    LET is_new = TRUE
    IF when_cmb IS NOT NULL THEN
       CALL when_cmb.addItem(notelist[curr_row].contnote_when,notelist[curr_row].contnote_when)
    END IF
END FUNCTION

PRIVATE FUNCTION delete_current_note()
    IF is_new THEN
       LET is_new = FALSE
    ELSE
       IF notelist[curr_row].contnote_rec_mstat = "N" THEN
          DELETE FROM contnote
           WHERE contnote_num = notelist[curr_row].contnote_num
       ELSE
          CALL set_mrec_change(curr_row,"D")
          UPDATE contnote
             SET contnote_rec_muser = notelist[curr_row].contnote_rec_muser,
                 contnote_rec_mtime = notelist[curr_row].contnote_rec_mtime,
                 contnote_rec_mstat = notelist[curr_row].contnote_rec_mstat
           WHERE contnote_num = notelist[curr_row].contnote_num
       END IF
    END IF
    CALL remove_current_element()
END FUNCTION

PRIVATE FUNCTION browse_notes(row)
    DEFINE row INT
    DEFINE arr DYNAMIC ARRAY OF RECORD
                   key INTEGER,
                   text STRING,
                   who_when STRING
               END RECORD
    DEFINE x INT
    FOR x=1 TO notelist.getLength()
        LET arr[x].key = x
        LET arr[x].text = notelist[x].contnote_text
        LET arr[x].who_when = notelist[x].contnote_rec_muser || " / "
                              || notelist[x].contnote_when
    END FOR
    OPEN WINDOW w_browse_notes WITH FORM "list1"
    DISPLAY ARRAY arr TO sr.* ATTRIBUTES(UNBUFFERED,DOUBLECLICK=accept)
        BEFORE DISPLAY
           CALL DIALOG.setCurrentRow("sr",row)
        AFTER DISPLAY
           IF NOT int_flag THEN
              CALL select_note(arr_curr())
           END IF
    END DISPLAY
    CLOSE WINDOW w_browse_notes
END FUNCTION

FUNCTION edit_notes(user_id, contact_num)
    DEFINE user_id t_user_id, contact_num INTEGER
    DEFINE tmp STRING
    LET current_user = user_id
    LET current_contact = contact_num
    OPEN WINDOW w_contnote WITH FORM "contnote"
    CALL load_notes(contact_num)
    CALL init_when_combobox()
    LET curr_row = 1
    CALL notelist_to_rec()
    INPUT BY NAME rec.* WITHOUT DEFAULTS ATTRIBUTES(UNBUFFERED)
          ON CHANGE contnote_when
             CALL save_current_note()
             CALL select_new_current()
          AFTER FIELD contnote_text
             CALL save_current_note()
          ON ACTION note_browse ATTRIBUTES(IMAGE="fa-list",TEXT="Browse")
             IF notelist.getLength()>1 THEN
                CALL save_current_note()
                CALL browse_notes(curr_row)
                NEXT FIELD contnote_text -- Resets edit cursor
             END IF
          ON ACTION note_append
             CALL save_current_note()
             CALL append_new_note()
             NEXT FIELD contnote_text -- Resets edit cursor
          ON ACTION note_copy
             LET tmp = rec.contnote_text
             CALL save_current_note()
             CALL append_new_note()
             LET rec.contnote_text = tmp
             NEXT FIELD contnote_text -- Resets edit cursor
          ON ACTION note_up
             IF curr_row>1 THEN
                CALL save_current_note()
                LET curr_row=curr_row-1
                LET rec.contnote_when = notelist[curr_row].contnote_when
                CALL select_note(curr_row)
                NEXT FIELD contnote_text -- Resets edit cursor
             END IF
          ON ACTION note_down
             IF curr_row<notelist.getLength() THEN
                CALL save_current_note()
                LET curr_row=curr_row+1
                LET rec.contnote_when = notelist[curr_row].contnote_when
                CALL select_note(curr_row)
                NEXT FIELD contnote_text -- Resets edit cursor
             END IF
          ON ACTION note_delete
             CALL delete_current_note()
             IF curr_row > notelist.getLength() THEN
                LET curr_row = notelist.getLength()
                IF curr_row == 0 THEN
                   CALL append_new_note()
                END IF
             END IF
             CALL notelist_to_rec()
             NEXT FIELD contnote_text -- Resets edit cursor
          AFTER INPUT
             CALL save_current_note()
    END INPUT
    CLOSE WINDOW w_contnote
END FUNCTION

