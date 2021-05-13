# WARNING: Locale must be UTF-8!

IMPORT com
IMPORT xml
IMPORT util

IMPORT FGL libutil
IMPORT FGL dbsync_contact

CONSTANT SERVICE_JSON   = "/mobile/dbsync/json"
CONSTANT SERVICE_XML    = "/mobile/dbsync/xml"
CONSTANT SERVICE_STOP   = "/mobile/dbsync/stop"
CONSTANT SERVICE_STATUS = "/mobile/dbsync/status"

DEFINE verbose BOOLEAN

MAIN
    DEFINE dbname, dbsrce, dbdriv, apik, uname, upswd STRING,
           port, i, s INTEGER, msg STRING

    CALL check_utf8() RETURNING s, msg
    IF s != 0 THEN
       CALL show_err(msg)
       EXIT PROGRAM 1
    END IF

    LET port = 8090 -- For dev
    CALL libutil.get_dbc_args()
         RETURNING dbname, dbsrce, dbdriv, uname, upswd
    FOR i = 1 TO num_args()
        CASE arg_val(i)
        WHEN "-p" LET i = i + 1 LET port = arg_val(i)
        WHEN "-k" LET i = i + 1 LET apik = arg_val(i)
        WHEN "-v" LET verbose = TRUE
        END CASE
    END FOR
    IF arg_val(1) == "-h"
    OR dbname IS NULL
    THEN
       DISPLAY "Usage: dbsync_mobile options ..."
       DISPLAY "   -d dbname"
       DISPLAY "   -f dbsrce"
       DISPLAY "   -o driver"
       DISPLAY "   -u user"
       DISPLAY "   -w pswd"
       DISPLAY "   -p port-num (when not using GAS)"
       DISPLAY "   -k google-api-key"
       EXIT PROGRAM 1
    END IF

    CALL show_verb("Starting dbsync server:")
    CALL show_verb("  Listening on port  : "|| NVL(port,"null"))
    CALL show_verb("  Database           : "||dbname)
    LET s = do_connect(dbname, dbsrce, dbdriv, uname, upswd)
    IF s !=0 THEN
       CALL show_err(SFMT("%1 %2",s,SQLERRMESSAGE))
       EXIT PROGRAM 1
    END IF
    CALL show_verb(SFMT("Database driver: %1", fgl_db_driver_type()))

    CALL dbsync_contacts_set_google_api_key( apik )

    CALL start_http(port)

    CALL show_verb("End of dbsync server...")

END MAIN

FUNCTION show_verb(msg)
    DEFINE msg STRING
    IF verbose THEN
       DISPLAY msg
    END IF
END FUNCTION

FUNCTION show_err(msg)
    DEFINE msg STRING
    DISPLAY "ERROR:", msg
END FUNCTION

FUNCTION start_http(port)
    DEFINE port INTEGER
    DEFINE req com.HttpServiceRequest,
           uri STRING

    -- Normally, the port is set by the GAS for load balancing
    IF port IS NOT NULL THEN
       CALL show_verb( SFMT("Setting FGLAPPSERVER to %1", port) )
       CALL fgl_setenv("FGLAPPSERVER", port)
    END IF

    CALL com.WebServiceEngine.SetOption("server_readwritetimeout",3600) --120)
    CALL com.WebServiceEngine.Start()

    WHILE TRUE
       TRY -- We can get -15565 if the GAS closes the TCP socket
          LET req = com.WebServiceEngine.GetHTTPServiceRequest(20)
       CATCH
          IF status==-15565 THEN
             CALL show_verb("TCP socket probably closed by GAS, stopping dbsync server process...")
             EXIT PROGRAM 0
          ELSE
             DISPLAY "Unexpected getHTTPServiceRequest() exception: ", status
             DISPLAY "Reason: ", sqlca.sqlerrm
             EXIT PROGRAM 1
          END IF
       END TRY
       IF req IS NULL THEN -- timeout
          CALL show_verb(SFMT("HTTP request timeout...: %1", CURRENT YEAR TO FRACTION))
          CONTINUE WHILE
       END IF
       # Dispatch according to service URI
       LET uri = req.getUrl()
       IF uri.getIndexOf(SERVICE_STOP,1)>1 THEN
          CALL req.sendTextResponse(200,NULL,"Service stopped")
          EXIT WHILE
       END IF
       IF process_request(uri, req) < 0 THEN
          CONTINUE WHILE -- Ignore unexpected request and continue
       END IF
    END WHILE
END FUNCTION

FUNCTION process_request(uri, req)
  DEFINE uri STRING, req com.HttpServiceRequest
  DEFINE method, header, format, cmd, res STRING,
         selist, selist_res dbsync_contact.t_selist,
         doc xml.DomDocument,
         n xml.DomNode

  # Check HTTP Verb
  LET method = req.getMethod()
  IF method IS NULL OR (method!="POST" AND method!="GET") THEN
     LET res = SFMT("Unexpected HTTP request method: %1", method)
     CALL show_err(res)
     CALL req.sendTextResponse(400,NULL,res)
     RETURN -2
  END IF

  # Status service
  IF method=="GET" AND uri.getIndexOf(SERVICE_STATUS,1)>1 THEN
     CALL req.sendTextResponse(200,NULL,dbsync_generate_status_text())
     RETURN 0
  END IF

  # Check URL
  IF uri.getIndexOf(SERVICE_JSON,1)>1 THEN
     LET format = "json"
  END IF
  IF uri.getIndexOf(SERVICE_XML,1)>1 THEN
     LET format = "xml"
  END IF
  IF format IS NULL THEN
     LET res = SFMT("Unexpected HTTP request type : %1", uri)
     CALL show_err(res)
     CALL req.sendTextResponse(400,NULL,res)
     RETURN -1
  END IF

  # Check mandatory header
  LET header = req.getRequestHeader("DBSync-Client")
  IF header IS NULL OR header!= "contact" THEN
     LET res = SFMT("Unexpected HTTP request header DBSync-Client: %1", header)
     CALL show_err(res)
     CALL req.sendTextResponse(400,NULL,res)
     RETURN -3
  END IF

  # Sync requests
  IF method=="POST" THEN

    IF format=="json" THEN
     TRY
       LET cmd = req.readTextRequest()
     CATCH
       CALL show_err(SFMT("Unexpected HTTP request read exception: %1", status))
     END TRY
     CALL show_verb( SFMT("json cmd [%1] (%2 Chars): %3",
                          CURRENT YEAR TO FRACTION, cmd.getLength(), util.JSON.format(cmd)) )
     TRY
       CALL util.JSON.parse(cmd,selist)
     CATCH
       CALL show_err(SFMT("JSON parsing error: %1", status))
       CALL req.sendTextResponse(500,NULL,"JSON parsing error")
     END TRY
    ELSE -- xml
     TRY
       LET doc = req.readXmlRequest()
       CALL show_verb( SFMT("xml cmd [%1] : %2",
                            CURRENT YEAR TO FRACTION, doc.saveToString()) )
       CALL xml.Serializer.DomToVariable(doc.getDocumentElement(),selist)
     CATCH
       CALL show_err(SFMT("XML deserialization failed: %1", status))
       CALL req.sendTextResponse(500,NULL,"XML deserialization ")
     END TRY
    END IF

    CALL dbsync_contacts_sync_server(selist.*) RETURNING selist_res.*

  ELSE -- GET

    CALL dbsync_contacts_get_request(uri) RETURNING selist_res.*

  END IF

  # Result

  IF format=="json" THEN
     TRY
       LET res = util.JSON.stringify(selist_res)
       CALL show_verb( SFMT("json res [%1] (%2 Chars): %3",
                       CURRENT YEAR TO FRACTION, res.getLength(), util.JSON.format(res) ))
     CATCH
       CALL show_err(SFMT("JSON stringify error: %1", status))
       CALL req.sendTextResponse(500,NULL,"JSON stringify error")
       RETURN -4
     END TRY
  ELSE -- xml
     TRY
       LET doc = xml.DomDocument.Create()
       LET n = doc.createDocumentFragment()
       CALL xml.Serializer.VariableToDom(selist_res,n)
       CALL doc.appendDocumentNode(n)
       CALL show_verb( SFMT("xml res [%1] : %2",
                            CURRENT YEAR TO FRACTION, doc.saveToString() ))
     CATCH
       CALL show_err(SFMT("XML serialization failed: %1", status))
       CALL req.sendTextResponse(500,NULL,"XML serialization failed")
       RETURN -4
     END TRY
  END IF

  CALL req.setResponseCharset("UTF-8")
  CALL req.setResponseHeader("dbsync-server","result")
  CALL req.setResponseHeader("Content-Type", SFMT("dbsync/%1",format))

  IF format=="json" THEN
     CALL req.sendTextResponse(200,NULL,res)
  ELSE -- xml
     CALL req.sendXmlResponse(200,NULL,doc)
  END IF

  RETURN 0

END FUNCTION
