IMPORT FGL libutil

FUNCTION create_database(tp,ws)
    DEFINE tp VARCHAR(20), ws BOOLEAN
    DEFINE tmp VARCHAR(200), s INTEGER

    WHENEVER ERROR CONTINUE
    DROP TABLE datafilter
    --
    DROP TABLE contnote
    DROP TABLE contact
    DROP TABLE city
    WHENEVER ERROR STOP

    IF tp=="cleanup" THEN
       RETURN
    END IF

    IF tp=="server" THEN

       LET s = libutil.sequence_drop("contact")
       --LET s = libutil.sequence_drop("contnote")

       CALL libutil.users_server_table()
       IF ws THEN
          CALL libutil.users_add(v_undef, NULL, v_undef_text, 1) -- Foreign key to contacts
          CALL libutil.users_add("max",   NULL, "Max Brand", 1)
          CALL libutil.users_add("mike",  NULL, "Mike Sharp", 1)
          CALL libutil.users_add("ted",   NULL, "Ted Philips", 1)
       END IF

       CALL libutil.datafilter_table()
       IF ws THEN
          -- Data filters for user "mike"
          LET tmp = " city_num = 1000 OR city_country IN ('France','Germany')"
          CALL libutil.datafilter_define("mike", "city", tmp)
          CALL libutil.datafilter_define("mike", "contact", "contact_city IN (select city_num FROM city WHERE"||tmp||")")
          -- Data filters for user "max"
          LET tmp = " city_num = 1000 OR city_country IN ('France','Spain')"
          CALL libutil.datafilter_define("max", "city", tmp)
          CALL libutil.datafilter_define("max", "contact", "contact_city IN (select city_num FROM city WHERE"||tmp||")")
          -- Data filters for user "ted"
          CALL libutil.datafilter_define("ted", "city", NULL)
          CALL libutil.datafilter_define("ted", "contact", NULL)
       END IF

    END IF

    -- Readonly table for the mobile, filled with city of the user area (some countries)
    -- Filtered in the mobile application program, according to datafilter.
    CREATE TABLE city (
         city_num INTEGER NOT NULL,
         city_name VARCHAR(30) NOT NULL,
         city_country VARCHAR(30) NOT NULL,
         PRIMARY KEY(city_num),
         UNIQUE (city_name, city_country)
    )
    INSERT INTO city VALUES ( 1000, v_undef, v_undef_text )
    INSERT INTO city VALUES ( 1001, "Paris", "France" )
    INSERT INTO city VALUES ( 1002, "London", "U.K." )
    INSERT INTO city VALUES ( 1003, "Berlin", "Germany" )
    INSERT INTO city VALUES ( 1004, "Madrid", "Spain" )
    INSERT INTO city VALUES ( 1005, "Rome", "Italy" )
    INSERT INTO city VALUES ( 1006, "Vienna", "Austria" )
    INSERT INTO city VALUES ( 1007, "Schiltigheim", "France" )
    INSERT INTO city VALUES ( 1008, "Vendenheim", "France" )
    INSERT INTO city VALUES ( 1009, "Bishheim", "France" )
    INSERT INTO city VALUES ( 1010, "Strasbourg", "France" )

    CREATE TABLE contact (
         contact_num INTEGER NOT NULL,
         contact_rec_muser VARCHAR(20) NOT NULL,
         contact_rec_mtime DATETIME YEAR TO FRACTION(3) NOT NULL,
         contact_rec_mstat CHAR(2) NOT NULL,
         contact_name VARCHAR(100) NOT NULL,
         contact_valid CHAR(1) NOT NULL,
         contact_street VARCHAR(100),
         contact_city INTEGER NOT NULL,
         contact_num_m VARCHAR(40),
         contact_num_w VARCHAR(40),
         contact_num_h VARCHAR(40),
         contact_user VARCHAR(20) NOT NULL,
         contact_loc_lon DECIMAL(10,6),
         contact_loc_lat DECIMAL(10,6),
         contact_photo_mtime DATETIME YEAR TO FRACTION(3),
         contact_photo BYTE,
         PRIMARY KEY(contact_num),
         UNIQUE (contact_name, contact_city), -- contact_street) for unique tests
         FOREIGN KEY (contact_city) REFERENCES city (city_num),
         FOREIGN KEY (contact_user) REFERENCES users (user_id)
    )
    IF NOT ws THEN
       LET s = libutil.sequence_create("contact",1000)
    ELSE
       INSERT INTO contact VALUES ( 1001, "admin", "2010-01-01 00:00:00.000", "S",
              "Max Brand",      "Y", "6 Rue de Kléber",       1007, "03-7645-2345",
              NULL, NULL, "max", NULL, NULL, NULL, NULL )
       INSERT INTO contact VALUES ( 1002, "admin", "2010-01-01 00:00:00.000", "S",
              "Carl Lansfield", "Y", "5 Rue Voltaire",  1008, "03-1111-2345",
              NULL, NULL, v_undef, NULL, NULL, NULL, NULL )
       INSERT INTO contact VALUES ( 1003, "admin", "2010-01-01 00:00:00.000", "S",
              "Mike Sharp",     "Y", "Rue du Canal",          1009, "03-9999-1111",
              NULL, NULL, "mike", NULL, NULL, NULL, NULL )
       INSERT INTO contact VALUES ( 1004, "admin", "2010-01-01 00:00:00.000", "S",
              "Ted Philips",    "Y", "5 Place Kléber",        1010, "03-9999-2345",
              NULL, NULL, "ted", NULL, NULL, NULL, NULL )
       INSERT INTO contact VALUES ( 1005, "admin", "2010-01-01 00:00:00.000", "S",
              "Clark Brinship", "Y", "2 Rue Rouge",           1007, "03-9999-2345",
              NULL, NULL, v_undef, NULL, NULL, NULL, NULL )
       INSERT INTO contact VALUES ( 1006, "admin", "2010-01-01 00:00:00.000", "S",
              "Mike Clamberg",  "Y", "3 Rue des Artisans",    1008, "03-7645-9999",
              NULL, NULL, v_undef, NULL, NULL, NULL, NULL )
       INSERT INTO contact VALUES ( 1007, "admin", "2010-01-01 00:00:00.000", "S",
              "Ted Fiztman",    "Y", "123 Ocean Av",          1002, "03-7645-9999",
              NULL, NULL, v_undef, NULL, NULL, NULL, NULL )
       INSERT INTO contact VALUES ( 1008, "admin", "2010-01-01 00:00:00.000", "S",
              "Patrick Kenzal", "Y", "8722 Main street",      1004, "03-9999-2345",
              NULL, NULL, v_undef, NULL, NULL, NULL, NULL )
       INSERT INTO contact VALUES ( 1009, "admin", "2010-01-01 00:00:00.000", "S",
              "Steve Baumer",   "Y", "231 Cardigon Bld",      1002, "03-9999-2345",
              NULL, NULL, v_undef, NULL, NULL, NULL, NULL )
       INSERT INTO contact VALUES ( 1010, "admin", "2010-01-01 00:00:00.000", "S",
              "Philip Desmond", "Y", "12 Kirt street",        1004, "03-7645-9999",
              NULL, NULL, v_undef, NULL, NULL, NULL, NULL )
       LET s = libutil.sequence_create("contact",2000)
    END IF

    CREATE TABLE contnote (
         contnote_num INTEGER NOT NULL,
         contnote_rec_muser VARCHAR(20) NOT NULL,
         contnote_rec_mtime DATETIME YEAR TO FRACTION(3) NOT NULL,
         contnote_rec_mstat CHAR(2) NOT NULL,
         contnote_contact INTEGER NOT NULL,
         contnote_when DATETIME YEAR TO FRACTION(3) NOT NULL,
         contnote_text VARCHAR(250),
         PRIMARY KEY(contnote_num),
         UNIQUE (contnote_contact, contnote_when),
         FOREIGN KEY (contnote_contact) REFERENCES contact (contact_num)
    )
    IF NOT ws THEN
       LET s = libutil.sequence_create("contnote",1000)
    ELSE
       INSERT INTO contnote VALUES ( 1001, "admin", "2010-01-01 00:00:00.000", "S",
              1001, "2014-01-01 11:45:00.000", "This customer is French" )
       INSERT INTO contnote VALUES ( 1002, "admin", "2010-01-01 00:00:00.000", "S",
              1001, "2014-01-02 12:43:00.000", "Send a gift for Xmass" )
       INSERT INTO contnote VALUES ( 1003, "admin", "2010-01-01 00:00:00.000", "S",
              1001, "2014-01-03 11:42:00.000", "Has many offices around the world" )
       INSERT INTO contnote VALUES ( 1004, "admin", "2010-01-01 00:00:00.000", "S",
              1002, "2014-01-01 15:15:00.000", "Next call: Friday the 12th in the afternoon" )
       LET s = libutil.sequence_create("contnote",2000)
    END IF

END FUNCTION
