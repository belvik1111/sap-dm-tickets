*&---------------------------------------------------------------------*
*& Include          YRST_GH_LCOND_DEAKT_SSC
*&---------------------------------------------------------------------*
*-----------------------------------------------------------------------
* Selektionsbildschirm
*-----------------------------------------------------------------------
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
SELECT-OPTIONS: s_bukrs  FOR yrst_gh_lcond-bukrs_send OBLIGATORY,
                s_matnr  FOR yrst_gh_lcond-matnr,
                s_bukrec FOR yrst_gh_lcond-bukrs_recv,
                s_werks  FOR yrst_gh_lcond-werks.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
SELECT-OPTIONS: s_mmsta  FOR marc-mmsta.
PARAMETERS:     p_monate TYPE i,
                p_best   AS CHECKBOX DEFAULT 'X',
                p_test   AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b2.

* Hinweis fuer den Produktivbetrieb (taegliche Einplanung, s. Review):
* P_TEST ist standardmaessig aktiv (Testlauf). Die Jobvariante fuer den
* taeglichen Hintergrundlauf MUSS P_TEST explizit deaktivieren, sonst
* werden nie Aenderungen gespeichert. Der Report macht den aktiven
* Testlauf zusaetzlich im Ausgabeprotokoll sichtbar (s. LCL, Methode
* DISPLAY), damit ein versehentlicher Testlauf im Batch sofort auffaellt.
