*&---------------------------------------------------------------------*
*& Include          YRST_GH_LCOND_DEAKT_EVT
*&---------------------------------------------------------------------*


*-----------------------------------------------------------------------
INITIALIZATION.
*-----------------------------------------------------------------------
* Artikelstatus aus der Parameterpflege vorbelegen, sonst Default 'A1'
  TRY.
      ycl_ca_bb_para=>get_param_as_range(
        EXPORTING piv_objtyp  = gc_param-objtyp
                  piv_objname = gc_param-objname
                  piv_param   = CONV #( gc_param-mmsta )
        CHANGING  pxt_range   = s_mmsta[] ).
    CATCH ycx_ca_bb_para ##NO_HANDLER.
  ENDTRY.

  IF s_mmsta[] IS INITIAL.
    APPEND VALUE #( sign = 'I' option = 'EQ' low = 'A1' ) TO s_mmsta.
  ENDIF.

*-----------------------------------------------------------------------
START-OF-SELECTION.
  " -----------------------------------------------------------------------
  DATA lo_app TYPE REF TO lcl_application.

  TRY.
      lo_app = NEW lcl_application( is_selection = VALUE #( bukrs_send  = s_bukrs[]
                                                            matnr       = s_matnr[]
                                                            bukrs_recv  = s_bukrec[]
                                                            werks       = s_werks[]
                                                            mmsta       = s_mmsta[]
                                                            monate      = p_monate
                                                            check_stock = p_best
                                                            testlauf    = p_test ) ).
      lo_app->run( ).

    CATCH lcx_error INTO DATA(lx_error).
      MESSAGE lx_error TYPE 'I' DISPLAY LIKE 'E'.
      LEAVE LIST-PROCESSING.
  ENDTRY.

  " -----------------------------------------------------------------------
END-OF-SELECTION.
*-----------------------------------------------------------------------
  lo_app->display( ).
