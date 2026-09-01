*&---------------------------------------------------------------------*
*& Include          YRST_GH_LCOND_DEAKT_LCL
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& Include  YRST_LCOND_DEAKT_C01   (Definitionen)
*&---------------------------------------------------------------------*

* Ausnahmeklasse
CLASS lcx_error DEFINITION INHERITING FROM cx_static_check FINAL
                CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_t100_message.

    CONSTANTS: BEGIN OF no_authorization,
                 msgid TYPE symsgid      VALUE 'YRST_LCOND',
                 msgno TYPE symsgno      VALUE '001',
                 attr1 TYPE scx_attrname VALUE 'MV_TEXT',
                 attr2 TYPE scx_attrname VALUE '',
                 attr3 TYPE scx_attrname VALUE '',
                 attr4 TYPE scx_attrname VALUE '',
               END OF no_authorization.

    CONSTANTS: BEGIN OF missing_parameter,
                 msgid TYPE symsgid      VALUE 'YRST_LCOND',
                 msgno TYPE symsgno      VALUE '002',
                 attr1 TYPE scx_attrname VALUE 'MV_TEXT',
                 attr2 TYPE scx_attrname VALUE '',
                 attr3 TYPE scx_attrname VALUE '',
                 attr4 TYPE scx_attrname VALUE '',
               END OF missing_parameter.

    CONSTANTS: BEGIN OF update_failed,
                 msgid TYPE symsgid      VALUE 'YRST_LCOND',
                 msgno TYPE symsgno      VALUE '003',
                 attr1 TYPE scx_attrname VALUE 'MV_TEXT',
                 attr2 TYPE scx_attrname VALUE '',
                 attr3 TYPE scx_attrname VALUE '',
                 attr4 TYPE scx_attrname VALUE '',
               END OF update_failed.

    DATA mv_text TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING textid   LIKE if_t100_message=>t100key OPTIONAL
                previous TYPE REF TO cx_root OPTIONAL
                iv_text  TYPE string OPTIONAL.
ENDCLASS.

*----------------------------------------------------------------------*
* Applikationsklasse - gesamte Ablauf- und Fachlogik
*----------------------------------------------------------------------*
CLASS lcl_application DEFINITION CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS constructor
      IMPORTING is_selection TYPE ty_s_selection
      RAISING   lcx_error.

    METHODS run     RAISING lcx_error.
    METHODS display.

  PROTECTED SECTION.

*   Datenzugriffe - fuer ABAP Unit in der Testklasse redefiniert
    METHODS select_delisted_articles
      RETURNING VALUE(rt_articles) TYPE ty_t_article.

    METHODS select_articles_with_stock
      IMPORTING it_articles        TYPE ty_t_article
      RETURNING VALUE(rt_articles) TYPE ty_t_article.

    METHODS select_lcond_entries
      IMPORTING it_articles     TYPE ty_t_article
      RETURNING VALUE(rt_lcond) TYPE ty_t_lcond.

    METHODS save_updates
      IMPORTING it_update TYPE ty_t_update
      RAISING   lcx_error.

  PRIVATE SECTION.

    TYPES: BEGIN OF ty_s_residency,
             sender   TYPE char4,
             receiver TYPE char4,
             months   TYPE i,
           END OF ty_s_residency.

    DATA: ms_selection    TYPE ty_s_selection,
          mt_log          TYPE ty_t_log,
          mv_months_def   TYPE i VALUE 6,
          mt_residency    TYPE SORTED TABLE OF ty_s_residency
                               WITH UNIQUE KEY sender receiver,
          mt_company_code TYPE HASHED TABLE OF t001 WITH UNIQUE KEY bukrs.
    CONSTANTS: BEGIN OF gc_log_type,
                 ok    TYPE c LENGTH 2 VALUE 'OK',
                 error TYPE c LENGTH 2 VALUE 'EX',
               END OF gc_log_type .

*   Ablaufschritte
    METHODS check_authorization RAISING lcx_error.

    METHODS remove_articles_with_stock
      CHANGING ct_articles TYPE ty_t_article.

    METHODS build_updates
      IMPORTING it_articles      TYPE ty_t_article
                it_lcond         TYPE ty_t_lcond
      RETURNING VALUE(rt_update) TYPE ty_t_update.

*   Parametrisierung / Fristen
    METHODS load_parameters RAISING lcx_error.

    METHODS get_residency_months
      IMPORTING iv_bukrs_send    TYPE bukrs
                iv_bukrs_recv    TYPE bukrs
      RETURNING VALUE(rv_months) TYPE i.

    METHODS is_due
      IMPORTING iv_bukrs_send TYPE bukrs
                iv_bukrs_recv TYPE bukrs
                iv_delisted   TYPE datum
      EXPORTING ev_months     TYPE i
                ev_due_date   TYPE datum
      RETURNING VALUE(rv_due) TYPE abap_bool.

    METHODS get_country
      IMPORTING iv_bukrs          TYPE bukrs
      RETURNING VALUE(rv_country) TYPE land1.

*   Bestandsprüfung - Selektion paketweise (vgl. UPDATE_PACKAGE)
    METHODS select_stock_package
      IMPORTING it_package         TYPE ty_t_article
      RETURNING VALUE(rt_articles) TYPE ty_t_article.

*   Persistenz / Änderungsbelege
    METHODS update_package
      IMPORTING it_package TYPE ty_t_lcond
      RAISING   lcx_error.

    METHODS write_change_document
      IMPORTING is_old TYPE yrst_gh_lcond
                is_new TYPE yrst_gh_lcond.

    METHODS build_object_id
      IMPORTING is_lcond            TYPE yrst_gh_lcond
      RETURNING VALUE(rv_object_id) TYPE cdobjectv.

*   Protokoll
    METHODS add_log_entry
      IMPORTING is_lcond      TYPE yrst_gh_lcond OPTIONAL
                iv_type       TYPE c
                iv_bukrs      TYPE bukrs  OPTIONAL
                iv_matnr      TYPE matnr  OPTIONAL
                iv_ausl_datum TYPE datum  OPTIONAL
                iv_months     TYPE i      OPTIONAL
                iv_due_date   TYPE datum  OPTIONAL
                iv_datbi_new  TYPE datbi  OPTIONAL
                iv_message    TYPE string OPTIONAL.

    METHODS get_statistics
      EXPORTING ev_total TYPE i
                ev_ok    TYPE i
                ev_error TYPE i.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Include  YRST_LCOND_DEAKT_CI1   (Implementierungen)
*&---------------------------------------------------------------------*

CLASS lcx_error IMPLEMENTATION.
  METHOD constructor.
    super->constructor( previous = previous ).
    me->mv_text = iv_text.
    CLEAR me->textid.
    IF textid IS INITIAL.
      if_t100_message~t100key = if_t100_message=>default_textid.
    ELSE.
      if_t100_message~t100key = textid.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_application IMPLEMENTATION.

*----------------------------------------------------------------------*
* Konstruktor
*----------------------------------------------------------------------*
  METHOD constructor.
    ms_selection = is_selection.

    load_parameters( ).

    SELECT bukrs, land1 FROM t001
      INTO CORRESPONDING FIELDS OF TABLE @mt_company_code.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Ablaufsteuerung
*----------------------------------------------------------------------*
  METHOD run.

*   (0) Berechtigung
    check_authorization( ).

*   (1) Ausgelistete Artikel je abgebendem Buchungskreis
    DATA(lt_articles) = select_delisted_articles( ).
    IF lt_articles IS INITIAL.
      RETURN.
    ENDIF.

*   (2) Bestandsfreiheit prüfen
    IF ms_selection-check_stock = abap_true.
      remove_articles_with_stock( CHANGING ct_articles = lt_articles ).
    ENDIF.
    CHECK lt_articles IS NOT INITIAL.

*   (3) Aktive LCOND-Einträge lesen, Residenzzeit je Relation prüfen
    DATA(lt_lcond)  = select_lcond_entries( lt_articles ).
    DATA(lt_update) = build_updates( it_articles = lt_articles
                                     it_lcond    = lt_lcond ).

*   (4) Abgrenzen inkl. Änderungsbelegen
    IF ms_selection-testlauf = abap_false AND lt_update IS NOT INITIAL.
      save_updates( lt_update ).
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Berechtigungsprüfung
*----------------------------------------------------------------------*
  METHOD check_authorization.
    AUTHORITY-CHECK OBJECT 'S_TABU_NAM'
             ID 'TABLE' FIELD gc_tabname
             ID 'ACTVT' FIELD '02'.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE lcx_error
        EXPORTING
          textid  = lcx_error=>no_authorization
          iv_text = CONV string( gc_tabname ).
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Ausgelistete Artikel selektieren
*----------------------------------------------------------------------*
  METHOD select_delisted_articles.

*   Ausgelistete Artikel je abgebendem Buchungskreis (spätestes Auslistungsdatum)
*   Hinweis (Review-Fix): Zuordnung Werk -> Buchungskreis konsistent ueber
*   T001W (Werk -> Bewertungskreis) -> T001K (Bewertungskreis -> BuKr),
*   nicht ueber die (nur zufaellig oft gueltige) Annahme BWKEY = WERKS.
    SELECT k~bukrs        AS bukrs_send,
           c~matnr        AS matnr,
           MAX( c~mmstd ) AS delisted_date
      FROM marc AS c
      INNER JOIN t001w AS w ON w~werks = c~werks
      INNER JOIN t001k AS k ON k~bwkey = w~bwkey
      WHERE k~bukrs IN @ms_selection-bukrs_send
        AND c~matnr IN @ms_selection-matnr
        AND c~mmsta IN @ms_selection-mmsta
        AND c~lvorm  = @space
      GROUP BY k~bukrs, c~matnr
      INTO CORRESPONDING FIELDS OF TABLE @rt_articles.

    IF rt_articles IS INITIAL.
      RETURN.
    ENDIF.

*   Artikel entfernen, die in mind. einem Werk des BuKr noch gelistet sind
    SELECT DISTINCT k~bukrs, c~matnr
      FROM marc AS c
      INNER JOIN t001w AS w ON w~werks = c~werks
      INNER JOIN t001k AS k ON k~bwkey = w~bwkey
      FOR ALL ENTRIES IN @rt_articles
      WHERE k~bukrs   = @rt_articles-bukrs_send
        AND c~matnr   = @rt_articles-matnr
        AND c~mmsta NOT IN @ms_selection-mmsta
        AND c~lvorm   = @space
      INTO TABLE @DATA(lt_still_listed).

    LOOP AT lt_still_listed INTO DATA(ls_listed).
      DELETE rt_articles WHERE bukrs_send = ls_listed-bukrs
                           AND matnr      = ls_listed-matnr.
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
* Bestandsprüfung ueber CDS View I_MATERIALSTOCK (MATDOC), LBBSA = '01'
*----------------------------------------------------------------------*
  METHOD select_articles_with_stock.

    DATA lt_package TYPE ty_t_article.

    IF it_articles IS INITIAL.
      RETURN.
    ENDIF.

*   Review-Fix (SAPSQL_STMNT_TOO_LARGE): FOR ALL ENTRIES mit zwei UND-
*   verknuepften Schluesselfeldern (MATNR + BUKRS_SEND) erzeugt pro Zeile
*   von IT_ARTICLES eine eigene ODER-verknuepfte Bedingungsgruppe im
*   SQL-Statement. Bei vielen Artikeln/BuKr-Kombinationen wird die vom
*   Datenbanksystem erlaubte Statementlaenge ueberschritten. Daher hier
*   paketweise Selektion (analog SAVE_UPDATES/UPDATE_PACKAGE).
    LOOP AT it_articles INTO DATA(ls_article).
      INSERT ls_article INTO TABLE lt_package.

      IF lines( lt_package ) >= gc_stock_check_package_size.
        rt_articles = VALUE #( BASE rt_articles
          ( LINES OF select_stock_package( lt_package ) ) ).
        CLEAR lt_package.
      ENDIF.
    ENDLOOP.

    IF lt_package IS NOT INITIAL.
      rt_articles = VALUE #( BASE rt_articles
        ( LINES OF select_stock_package( lt_package ) ) ).
    ENDIF.

  ENDMETHOD.

  METHOD select_stock_package.

*   Hinweis (Review-Fix): direkt mit FOR ALL ENTRIES auf den tatsaechlichen
*   (BuKr, Artikel)-Paaren selektieren statt ueber zwei getrennte Ranges
*   (Kreuzprodukt aus allen BuKr x allen Artikeln, das anschliessend wieder
*   auf die echten Paare gefiltert wurde).
*   T001W enthaelt keinen Buchungskreis -> Zuordnung ueber den Bewertungs-
*   kreis (T001W-BWKEY) auf T001K-BUKRS.
    SELECT s~material AS matnr,
           k~bukrs    AS bukrs_send
      FROM i_materialstock AS s
      INNER JOIN t001w AS w ON w~werks = s~plant
      INNER JOIN t001k AS k ON k~bwkey = w~bwkey
      FOR ALL ENTRIES IN @it_package
      WHERE s~material           = @it_package-matnr
        AND k~bukrs               = @it_package-bukrs_send
        AND s~inventorystocktype  = @gc_stock_status
      GROUP BY s~material, k~bukrs
      HAVING SUM( s~matlwrhsstkqtyinmatlbaseunit ) > 0
      INTO TABLE @DATA(lt_stock).
*       matlwrhsstkqtyinmatlbaseunit AS labst

    rt_articles = CORRESPONDING #( lt_stock ).

  ENDMETHOD.

  METHOD remove_articles_with_stock.

    DATA(lt_with_stock) = select_articles_with_stock( ct_articles ).

    LOOP AT lt_with_stock INTO DATA(ls_stock).
      add_log_entry( iv_type    = gc_log_type-error
                     iv_bukrs   = ls_stock-bukrs_send
                     iv_matnr   = ls_stock-matnr
                     iv_message = CONV string( TEXT-m01 ) ). " Bestand vorhanden
      DELETE ct_articles WHERE bukrs_send = ls_stock-bukrs_send
                           AND matnr      = ls_stock-matnr.
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
* Aktive LCOND-Einträge lesen
*----------------------------------------------------------------------*
  METHOD select_lcond_entries.

    CHECK it_articles IS NOT INITIAL.

    SELECT * FROM yrst_gh_lcond
      FOR ALL ENTRIES IN @it_articles
      WHERE bukrs_send  = @it_articles-bukrs_send
        AND matnr       = @it_articles-matnr
        AND bukrs_recv IN @ms_selection-bukrs_recv
        AND werks      IN @ms_selection-werks
        AND datbi      >= @sy-datum
      INTO TABLE @rt_lcond.

  ENDMETHOD.

*----------------------------------------------------------------------*
* Updates aufbauen (Fälligkeit je Relation prüfen)
*----------------------------------------------------------------------*
  METHOD build_updates.
    DATA: lv_months   TYPE i,
          lv_due_date TYPE datum.

    LOOP AT it_lcond INTO DATA(ls_lcond).

      DATA(ls_article) = VALUE ty_s_article(
                           it_articles[ bukrs_send = ls_lcond-bukrs_send
                                        matnr      = ls_lcond-matnr ] OPTIONAL ).
      CHECK ls_article IS NOT INITIAL.

*     Review-Fix: Saetze, die erst in der Zukunft gueltig werden (DATAB > heute),
*     nicht automatisch abgrenzen - sonst wuerde DATBI < DATAB entstehen.
*     Text-Element m03 in SE38 zu pflegen, z.B. "Eintrag beginnt erst in der
*     Zukunft - keine automatische Abgrenzung".
      IF ls_lcond-datab > sy-datum.
        add_log_entry( is_lcond      = ls_lcond
                       iv_type       = gc_log_type-error
                       iv_ausl_datum = ls_article-delisted_date
                       iv_message    = CONV string( TEXT-m03 ) ).
        CONTINUE.
      ENDIF.

      DATA(lv_due) = is_due( EXPORTING iv_bukrs_send = ls_lcond-bukrs_send
                                       iv_bukrs_recv = ls_lcond-bukrs_recv
                                       iv_delisted   = ls_article-delisted_date
                             IMPORTING ev_months     = lv_months
                                       ev_due_date   = lv_due_date ).

      IF lv_due = abap_false.
        add_log_entry( is_lcond      = ls_lcond
                       iv_type       = gc_log_type-error
                       iv_ausl_datum = ls_article-delisted_date
                       iv_months     = lv_months
                       iv_due_date   = lv_due_date
                       iv_message    = CONV string( TEXT-m02 ) ). " Frist läuft noch
        CONTINUE.
      ENDIF.

      DATA(ls_new) = ls_lcond.
*     Abgrenzung zum Tagesdatum: DATBI bleibt heute noch gueltig, ab morgen
*     inaktiv. Falls fachlich stattdessen "ab heute bereits inaktiv" gewuenscht
*     ist, hier auf sy-datum - 1 aendern (bitte mit Fachbereich bestaetigen).
      ls_new-datbi = sy-datum.

      APPEND VALUE #( old = ls_lcond new = ls_new ) TO rt_update.

      add_log_entry( is_lcond      = ls_lcond
                     iv_type       = gc_log_type-ok
                     iv_ausl_datum = ls_article-delisted_date
                     iv_months     = lv_months
                     iv_due_date   = lv_due_date
                     iv_datbi_new  = ls_new-datbi ).
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
* Parametrisierung
*----------------------------------------------------------------------*
  METHOD load_parameters.

    DATA lt_range TYPE RANGE OF char40.

    TRY.
*       Default-Residenzzeit
        ycl_ca_bb_para=>get_param_as_range(
          EXPORTING piv_objtyp  = gc_param-objtyp
                    piv_objname = gc_param-objname
                    piv_param   = gc_param-res_def
          CHANGING  pxt_range   = lt_range ).
        IF lt_range IS NOT INITIAL.
          mv_months_def = lt_range[ 1 ]-low.
        ENDIF.

*       Relationen im Format <Sender>/<Empfaenger>=<Monate>, z.B. DE/PL=0
        CLEAR lt_range.
        ycl_ca_bb_para=>get_param_as_range(
          EXPORTING piv_objtyp  = gc_param-objtyp
                    piv_objname = gc_param-objname
                    piv_param   = CONV #( gc_param-res_rel )
          CHANGING  pxt_range   = lt_range ).

*       Review-Fix: Parsing der Relationen war bisher auskommentiert, wodurch
*       MT_RESIDENCY immer leer blieb und GET_RESIDENCY_MONTHS ausschliesslich
*       den globalen Default lieferte (Kernanforderung "DE->PL sofort,
*       AT->PL nach 6 Monaten" war dadurch nicht wirksam).
        LOOP AT lt_range INTO DATA(ls_rel).
          SPLIT ls_rel-low AT '/' INTO DATA(lv_sender) DATA(lv_rest).
          SPLIT lv_rest    AT '=' INTO DATA(lv_recv)   DATA(lv_months).

          CONDENSE lv_sender.
          CONDENSE lv_recv.
          CONDENSE lv_months.

*         Ungueltige/unvollstaendige Customizing-Zeilen ueberspringen statt
*         mit CX_SY_CONVERSION_NO_NUMBER abzubrechen.
          CHECK lv_sender IS NOT INITIAL
            AND lv_recv   IS NOT INITIAL
            AND lv_months CO '0123456789'.

          INSERT VALUE #( sender   = lv_sender
                          receiver = lv_recv
                          months   = CONV i( lv_months ) )
                 INTO TABLE mt_residency.
        ENDLOOP.

      CATCH ycx_ca_bb_para INTO DATA(lx_para).
        RAISE EXCEPTION TYPE lcx_error
          EXPORTING
            textid   = lcx_error=>missing_parameter
            previous = lx_para
            iv_text  = CONV string( gc_param-res_rel ).
    ENDTRY.

  ENDMETHOD.

  METHOD get_residency_months.

*   1. Übersteuerung vom Selektionsbild
    IF ms_selection-monate IS NOT INITIAL.
      rv_months = ms_selection-monate .
      RETURN.
    ENDIF.

*   2. Relation Buchungskreis -> Buchungskreis
    TRY.
        rv_months = mt_residency[ sender   = iv_bukrs_send
                                  receiver = iv_bukrs_recv ]-months.
        RETURN.
      CATCH cx_sy_itab_line_not_found ##NO_HANDLER.
    ENDTRY.

*   3. Relation Land -> Land
    TRY.
        rv_months = mt_residency[ sender   = get_country( iv_bukrs_send )
                                  receiver = get_country( iv_bukrs_recv ) ]-months.
        RETURN.
      CATCH cx_sy_itab_line_not_found ##NO_HANDLER.
    ENDTRY.

*   4. Default
    rv_months = mv_months_def.
  ENDMETHOD.

  METHOD is_due.

    ev_months = get_residency_months( iv_bukrs_send = iv_bukrs_send
                                      iv_bukrs_recv = iv_bukrs_recv ).

    CALL FUNCTION 'RP_CALC_DATE_IN_INTERVAL'
      EXPORTING
        date      = iv_delisted
        days      = 0
        months    = ev_months
        signum    = '+'
        years     = 0
      IMPORTING
        calc_date = ev_due_date.

    rv_due = xsdbool( ev_due_date <= sy-datum ).
  ENDMETHOD.

  METHOD get_country.
    rv_country = VALUE #( mt_company_code[ bukrs = iv_bukrs ]-land1 OPTIONAL ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* Persistenz
*----------------------------------------------------------------------*
  METHOD save_updates.

    DATA lt_package TYPE ty_t_lcond.

    LOOP AT it_update INTO DATA(ls_update).

      write_change_document( is_old = ls_update-old
                             is_new = ls_update-new ).

      APPEND ls_update-new TO lt_package.

      IF lines( lt_package ) >= gc_package_size.
        update_package( lt_package ).
        CLEAR lt_package.
      ENDIF.
    ENDLOOP.

    IF lt_package IS NOT INITIAL.
      update_package( lt_package ).
    ENDIF.

  ENDMETHOD.

  METHOD update_package.

    UPDATE yrst_gh_lcond FROM TABLE @it_package.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE lcx_error
        EXPORTING
          textid  = lcx_error=>update_failed
          iv_text = CONV string( gc_tabname ).
    ENDIF.
    COMMIT WORK AND WAIT.

  ENDMETHOD.

*----------------------------------------------------------------------*
* Änderungsbelege
*----------------------------------------------------------------------*
  METHOD write_change_document.

    DATA(lv_object_id) = build_object_id( is_new ).

    CALL FUNCTION 'CHANGEDOCUMENT_OPEN'
      EXPORTING
        objectclass      = gc_cdobjclas
        objectid         = lv_object_id
      EXCEPTIONS
        sequence_invalid = 1
        OTHERS           = 2.
    CHECK sy-subrc = 0.

    CALL FUNCTION 'YRST_GH_LCOND_WRITE_DOCUMENT'   " SCDO-generiert
      EXPORTING
        objectid          = lv_object_id
        tcode             = sy-tcode
        utime             = sy-uzeit
        udate             = sy-datum
        username          = sy-uname
        n_yrst_gh_lcond   = is_new
        o_yrst_gh_lcond   = is_old
        upd_yrst_gh_lcond = 'U'.

    CALL FUNCTION 'CHANGEDOCUMENT_CLOSE'
      EXPORTING
        objectclass = gc_cdobjclas
        objectid    = lv_object_id
      EXCEPTIONS
        OTHERS      = 1.

  ENDMETHOD.

  METHOD build_object_id.
    rv_object_id = |{ is_lcond-bukrs_send }{ is_lcond-matnr }| &&
                   |{ is_lcond-bukrs_recv }{ is_lcond-vlfkz }| &&
                   |{ is_lcond-werks }{ is_lcond-datab }|.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Protokoll
*----------------------------------------------------------------------*
  METHOD add_log_entry.

    APPEND VALUE #( type       = iv_type
                    bukrs_send = COND #( WHEN is_lcond IS NOT INITIAL
                                         THEN is_lcond-bukrs_send
                                         ELSE iv_bukrs )
                    matnr      = COND #( WHEN is_lcond IS NOT INITIAL
                                         THEN is_lcond-matnr
                                         ELSE iv_matnr )
                    ausl_datum = iv_ausl_datum
                    monate     = iv_months
                    stichtag   = iv_due_date
                    bukrs_recv = is_lcond-bukrs_recv
                    vlfkz      = is_lcond-vlfkz
                    werks      = is_lcond-werks
                    datbi_alt  = is_lcond-datbi
                    datbi_neu  = iv_datbi_new
                    meldung    = iv_message ) TO mt_log.

  ENDMETHOD.

  METHOD get_statistics.
    ev_total = lines( mt_log ).
    ev_ok    = REDUCE i( INIT x = 0 FOR ls IN mt_log
                         NEXT x = COND #( WHEN ls-type = gc_log_type-ok
                                          THEN x + 1 ELSE x ) ).
    ev_error = ev_total - ev_ok.
  ENDMETHOD.

  METHOD display.

    DATA lo_alv TYPE REF TO cl_salv_table.

    SORT mt_log BY type bukrs_send matnr bukrs_recv.

*   Review-Fix: Testlauf/Produktivlauf im Ausgabeprotokoll deutlich
*   sichtbar machen (v.a. relevant fuer den taeglichen Hintergrundjob,
*   dessen Variante P_TEST explizit deaktivieren muss).
*   Text-Elemente s04/s05 in SE38 zu pflegen, z.B.
*   s04 = "TESTLAUF - es wurden KEINE Aenderungen gespeichert!"
*   s05 = "Produktivlauf - Aenderungen wurden gespeichert."
    IF ms_selection-testlauf = abap_true.
      WRITE: / TEXT-s04 COLOR COL_NEGATIVE.
    ELSE.
      WRITE: / TEXT-s05 COLOR COL_POSITIVE.
    ENDIF.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = lo_alv
                                CHANGING  t_table      = mt_log ).
        lo_alv->get_functions( )->set_all( ).
        lo_alv->get_columns( )->set_optimize( ).
        lo_alv->get_display_settings( )->set_list_header( TEXT-t01 ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx_salv).
        MESSAGE lx_salv TYPE 'I' DISPLAY LIKE 'E'.
    ENDTRY.

    get_statistics( IMPORTING ev_total = DATA(lv_total)
                              ev_ok    = DATA(lv_ok)
                              ev_error = DATA(lv_error) ).
    WRITE: / TEXT-s01, lv_total,
           / TEXT-s02, lv_ok,
           / TEXT-s03, lv_error.

  ENDMETHOD.

ENDCLASS.
