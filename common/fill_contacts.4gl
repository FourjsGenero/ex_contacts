IMPORT util

SCHEMA contacts

TYPE t_contact RECORD
         contact_num LIKE contact.contact_num,
         contact_rec_muser LIKE contact.contact_rec_muser,
         contact_rec_mtime LIKE contact.contact_rec_mtime,
         contact_rec_mstat LIKE contact.contact_rec_mstat,
         contact_name LIKE contact.contact_name,
         contact_valid LIKE contact.contact_valid,
         contact_street LIKE contact.contact_street,
         contact_city LIKE contact.contact_city,
         contact_num_m LIKE contact.contact_num_m,
         contact_num_w LIKE contact.contact_num_w,
         contact_num_h LIKE contact.contact_num_h,
         contact_photo LIKE contact.contact_photo
     END RECORD

MAIN
    DEFINE rec t_contact, i INT

    CONNECT TO "contacts+driver='dbmpgs'" USER "pgsuser" USING "fourjs"

    LOCATE rec.contact_photo IN FILE "currphoto.tmp"

    DELETE FROM contact WHERE contact_num >=10000
    FOR i=1 TO 2000
display i
if i mod 100 == 0 then sleep 1 end if
       LET rec.contact_num = 10000 + i
       LET rec.contact_rec_muser = "admin"
       LET rec.contact_rec_mtime = util.Datetime.toUTC(CURRENT YEAR TO FRACTION(3))
       LET rec.contact_rec_mstat = "S"
       LET rec.contact_name  = "Contact #"||i
       LET rec.contact_valid = "Y"
       LET rec.contact_street = "mbxmvcbmbxchsdf"
       LET rec.contact_city = 1002
       LET rec.contact_num_m = 99882998234+ i
       LET rec.contact_num_w = 9982734234-i
       LET rec.contact_num_h = 89234879+i*5
       LET rec.contact_photo = NULL
       INSERT INTO contact VALUES ( rec.* )
   END FOR

END MAIN
