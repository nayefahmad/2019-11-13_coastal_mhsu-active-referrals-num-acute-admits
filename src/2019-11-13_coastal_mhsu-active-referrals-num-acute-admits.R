
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

#+ rest

d1_max_referral <- 
  vw_paris_ref %>% 
  filter(CommunityProgramGroup == "Mental Health & Addictions", 
         CommunityRegion %in% c("Coastal Urban",
                                "Coastal Rural")) %>% 
  select(ReferralDate) %>% 
  collect() %>% 
  pull(ReferralDate) %>% 
  max()


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
                           

df2.admits <- 
  vw_admission_discharge %>% 
  filter(encntr_type_class_grp_at_ad == "Inpatient", 
         admit_date_id >= "20150101") %>% 
  select(patient_id, 
         admit_date_id, 
         facility_short_name_at_admit) %>% 
  collect()


# join mhsu referrals and all-sites admits 
df3.mhsu_admits <- 
  df1.paris_mhsu %>% 
  inner_join(df2.admits, 
            by = c("PatientID" = "patient_id")) %>% 
  arrange(admit_date_id, 
          PatientID) %>% 
  mutate(admit_date = ymd(admit_date_id))

# view: 
index <- 1900  # index for slicing
df3.mhsu_admits %>% 
  slice(index:(index+99)) %>% 
  datatable(extensions = 'Buttons',
            options = list(dom = 'Bfrtip', 
                           buttons = c('excel', "csv")))

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

  
            
