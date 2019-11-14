
#'--- 
#' title: "Coastal: PARIS MHSU clients with acute encounters "
#' author: "Nayef Ahmad"
#' date: "2019-11-13"
#' output: 
#'   html_document: 
#'     keep_md: yes
#'     code_folding: show
#'     toc: true
#'     toc_float:
#'       collapsed: false
#'     toc_folding: false
#' ---
#' 

#+ lib, include = FALSE
library(tidyverse)
library(denodoExtractor)
library(lubridate)
library(DT)

setup_denodo()
setup_sql_server()

cnx <<- DBI::dbConnect(odbc::odbc(), dsn = "cnx_SPDBSCSTA001")

vw_paris_ref <- dplyr::tbl(cnx, dbplyr::in_schema("[CommunityMart].[dbo]", 
                                                  "[vwPARISReferral]"))

vw_nunit_classification <- dplyr::tbl(cnx, dbplyr::in_schema("[ADRMart].[Dim]", 
                                                             "[LocationGrp]"))

#+ rest

#' # Todo: 
#' 
#' 

#' # Data 
#' 
#' 
d1_max_referral <- 
  vw_paris_ref %>%  # [vwPARISReferral]
  filter(CommunityProgramGroup == "Mental Health & Addictions", 
         CommunityRegion %in% c("Coastal Urban",
                                "Coastal Rural")) %>% 
  select(ReferralDate) %>% 
  collect() %>% 
  pull(ReferralDate) %>% 
  max()


#' Nursing unit classification: 
#' 

df0.n_units <- 
  vw_nunit_classification %>%  # [ADRMart].[Dim].[LocationGrp]
  collect() %>% 
  
  # add col is_acute
  mutate(is_acute = case_when((IsHospice == 0 &
                                IsTCU == 0 & 
                                IsTMH == 0 & 
                                IsRcExtended == 0 & 
                                IsRehab == 0 & 
                                IsDaycare == 0) ~ 1,
                              TRUE ~ 0)) %>% 
  filter(is_acute == 1)

df0.n_units %>% 
  datatable(extensions = 'Buttons',
            options = list(dom = 'Bfrtip', 
                           buttons = c('excel', "csv")))
                           

#' All patients in PARISReferral with MHSU program, from Coastal: 
#' 

df1.paris_mhsu <- 
  vw_paris_ref %>% 
  filter(CommunityProgramGroup == "Mental Health & Addictions", 
         CommunityRegion %in% c("Coastal Urban",
                                "Coastal Rural")) %>% 
  select(PatientID, 
         CommunityProgramGroup) %>% 
  collect() %>% 
  arrange(PatientID) %>% 
  distinct()
  
# df1.paris_mhsu %>% 
#   head(500) %>% 
#   datatable(extensions = 'Buttons',
#             options = list(dom = 'Bfrtip', 
#                            buttons = c('excel', "csv")))
                           
sites_param <- c("VGH", 
                 "UBCH",
                 "LGH", 
                 "PRGH",
                 "SSH", 
                 "SGH",
                 "SPH", 
                 "MSJ")

#' All inpatient either admit or discharge encounters at "regional hospitals"
#' since 2015-01-01. Only looking at units classified as "isAcute" 
#' 

df2.admits <- 
  vw_admission_discharge %>%  # publish.admission_discharge
  filter(encntr_type_class_grp_at_ad == "Inpatient", 
         admit_date_id >= "20150101", 
         (facility_short_name_at_admit %in% sites_param |
            facility_short_name_at_disch %in% sites_param)) %>% 
  select(patient_id, 
         admit_date_id, 
         facility_short_name_at_admit, 
         facility_short_name_at_disch ,
         nursing_unit_desc_at_admit, 
         nursing_unit_desc_at_disch) %>% 
  collect() %>% 
  filter((nursing_unit_desc_at_admit %in% df0.n_units$LocationGrpDescription | 
            nursing_unit_desc_at_disch %in% df0.n_units$LocationGrpDescription))

#' Now join the 2 datasets: 
#' 

# join mhsu referrals and all-sites admits 
df3.mhsu_admits <- 
  df1.paris_mhsu %>% 
  inner_join(df2.admits, 
            by = c("PatientID" = "patient_id")) %>% 
  arrange(admit_date_id, 
          PatientID) %>% 
  mutate(admit_date = ymd(admit_date_id))

# view: 
index <- sample(30000, 1)  # index for slicing
df3.mhsu_admits %>% 
  slice(index:(index+99)) %>% 
  datatable(extensions = 'Buttons',
            options = list(dom = 'Bfrtip', 
                           buttons = c('excel', "csv")))

#' Next, we have to filter to make sure that either the admit or disch n_unit is
#' in the is_acute category: 
#' 

  


#' # Plots 
#' 

df4.mhsu_admits_by_day <- 
  df3.mhsu_admits %>% 
  fill_dates(admit_date, 
             "2015-01-01", 
             "2019-11-13") %>% 
  count(dates_fill)
  
# tbl
df4.mhsu_admits_by_day %>% 
  datatable(extensions = 'Buttons',
            options = list(dom = 'Bfrtip', 
                           buttons = c('excel', "csv")))
                           
# plot 
df4.mhsu_admits_by_day %>% 
  ggplot(aes(x = dates_fill, 
             y = n)) + 
  geom_point(alpha = 0.3) + 
  geom_smooth()

  
            

#' # Appendix 
#' 
#' These are the queries for pulling data: 
#' 
# CommunityMart PARISReferral View: 
vw_paris_ref %>% 
  filter(CommunityProgramGroup == "Mental Health & Addictions", 
         CommunityRegion %in% c("Coastal Urban",
                                "Coastal Rural")) %>% 
  select(PatientID, 
         CommunityProgramGroup) %>% 
  show_query()

# denodo admission_discharge: 
vw_admission_discharge %>% 
  filter(encntr_type_class_grp_at_ad == "Inpatient", 
         admit_date_id >= "20150101", 
         (facility_short_name_at_admit %in% sites_param |
            facility_short_name_at_disch %in% sites_param)) %>% 
  select(patient_id, 
         admit_date_id, 
         facility_short_name_at_admit, 
         facility_short_name_at_disch) %>% 
  show_query()
