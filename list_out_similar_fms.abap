REPORT zfm_similarity_alv.

* Selection screen for date range
PARAMETERS: p_date_from TYPE sy-datum OBLIGATORY,
            p_date_to   TYPE sy-datum OBLIGATORY.

* Validate that the date range is not more than 5 months
AT SELECTION-SCREEN.
  DATA: lv_months_diff TYPE i.

  " Calculate the number of months between the two dates
  lv_months_diff = ( p_date_to - p_date_from ) / 30.0.

  " Validate that the date range is no more than 5 months
  IF lv_months_diff > 5.
    MESSAGE 'Date range must not be more than 5 months.' TYPE 'E'.
  ENDIF.

  " Validate that the start date is not greater than the end date
  IF p_date_from > p_date_to.
    MESSAGE 'Start date must not be greater than end date.' TYPE 'E'.
  ENDIF.

* Structures for storing FM details
TYPES: BEGIN OF ty_fm_info,
         custom_fm_name TYPE funcname,
         standard_fm_name TYPE funcname,
         created_by TYPE uname,
         created_on TYPE datum,
       END OF ty_fm_info.

* Tables to hold function modules data
DATA: lt_custom_fms TYPE TABLE OF ty_fm_info,
      lt_standard_fms TYPE TABLE OF ty_fm_info,
      lt_similar_fms TYPE TABLE OF ty_fm_info,
      lt_final_list TYPE TABLE OF ty_fm_info.

* Function module to calculate similarity ratio
DATA: lv_name_similarity TYPE decfloat34,
      lv_code_similarity TYPE decfloat34.

* Variables to hold FM code
DATA: lt_custom_code TYPE TABLE OF string,
      lt_standard_code TYPE TABLE OF string.

* Threshold for similarity
CONSTANTS: c_similarity_threshold TYPE decfloat34 VALUE 0.8.

START-OF-SELECTION.

* Step 1: Fetch custom FMs based on date range and standard FMs
SELECT funcname, uname, cdate INTO TABLE lt_custom_fms
FROM tfdir
WHERE ( funcname LIKE 'Z%' OR funcname LIKE 'Y%' )
  AND cdate BETWEEN p_date_from AND p_date_to.

SELECT funcname, uname, cdate INTO TABLE lt_standard_fms
FROM tfdir
WHERE funcname NOT LIKE 'Z%' AND funcname NOT LIKE 'Y%'.


* Step 2: Compare function module names for similarity
LOOP AT lt_custom_fms INTO DATA(ls_custom_fm).
  LOOP AT lt_standard_fms INTO DATA(ls_standard_fm).
    lv_name_similarity = cl_abap_char_utilities=>similarity_ratio(
                           EXPORTING first  = ls_custom_fm-fm_name
                                     second = ls_standard_fm-fm_name ).
    IF lv_name_similarity >= c_similarity_threshold.
      APPEND ls_custom_fm TO lt_similar_fms.
      EXIT. " If one match is found, move to the next custom FM
    ENDIF.
  ENDLOOP.
ENDLOOP.

* Step 3: Compare code similarity for the identified FMs
LOOP AT lt_similar_fms INTO DATA(ls_similar_fm).
  * Fetch the code of the custom function module
  CALL FUNCTION 'RS_GET_ALL_INCLUDES'
    EXPORTING funcname = ls_similar_fm-fm_name
    TABLES    source    = lt_custom_code.

  * Loop through standard function modules
  LOOP AT lt_standard_fms INTO ls_standard_fm.
    * Fetch the code of the standard function module
    CALL FUNCTION 'RS_GET_ALL_INCLUDES'
      EXPORTING funcname = ls_standard_fm-fm_name
      TABLES    source    = lt_standard_code.

    * Compare code similarity using your own algorithm or ABAP Utilities
    lv_code_similarity = cl_abap_char_utilities=>similarity_ratio(
                           EXPORTING first  = CONCATENATE lt_custom_code
                                     second = CONCATENATE lt_standard_code ).

    IF lv_code_similarity >= c_similarity_threshold.
      * Append to final list if both name and code are similar
      DATA(ls_final_fm) = VALUE ty_fm_info(
                            custom_fm_name = ls_similar_fm-fm_name
                            standard_fm_name = ls_standard_fm-fm_name
                            created_by = ls_similar_fm-created_by
                            created_on = ls_similar_fm-created_on ).
      APPEND ls_final_fm TO lt_final_list.
      EXIT.
    ENDIF.

    CLEAR: lt_standard_code.
  ENDLOOP.
  CLEAR: lt_custom_code.
ENDLOOP.

* Step 4: Display the result in an ALV grid
IF lt_final_list IS NOT INITIAL.
  TRY.
      DATA: lo_alv TYPE REF TO cl_salv_table.

      " Create ALV grid instance
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_alv
        CHANGING  t_table      = lt_final_list ).

      " Set ALV display options
      lo_alv->get_display_settings( )->set_striped_pattern( abap_true ). " Add zebra pattern
      lo_alv->get_columns( )->set_optimize( abap_true ).                 " Optimize column width

      " Display the ALV
      lo_alv->display( ).

    CATCH cx_salv_msg INTO DATA(lx_msg).
      MESSAGE lx_msg TYPE 'E'.
  ENDTRY.
ELSE.
  WRITE: / 'No matching function modules found in the selected date range.'.
ENDIF.
