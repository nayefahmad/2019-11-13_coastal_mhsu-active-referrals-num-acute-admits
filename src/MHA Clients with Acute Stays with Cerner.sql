-- DS4987  
-- Acute ALOS (regional hospitals) for Active Coastal MHA clients by period


-----------------------------------
--		Nursing Unit Classification Using Denodo AD data - Oct 3, 2019 by Flora
-----------------------------------
	--This is a temp solution to include Coastal data. It might need to be updated if there are better solutions to use Denodo AD data
	--The Nursing Unit classification is at the unit level only. It doesn't include TCU methodology for LGH (5E)
	--Duplication on MSJ & Rmd: M2W, M3W - Delete PHC M3w from dim.LocationGroup

	--Distinct nursing units for 9 VCH regional acute sites (a combination of admission units and discharge units)
	drop table if exists #tempDenodoADUnits

	-- admit units 
	select distinct facility_short_name_at_admit	as FacilityShortName
		, nursing_unit_short_desc_at_admit			as NursingUnit
		, nursing_unit_desc_at_admit				as NursingUnitDesc
	
	into #tempDenodoADUnits
	
	from [pre_publish_analytics].[interface].[admission_discharge_deidentified_vw]
	where facility_short_name_at_admit in ('VGH', 'UBCH', 'RHS', 'LGH', 'PRGH', 'SSH', 'SGH', 'SPH', 'MSJ')
		and nursing_unit_short_desc_at_admit not in ('Invalid', 'Not provided')
	
	union
	
	-- disch units 
	select distinct facility_short_name_at_disch	as FacilityShortName
		, nursing_unit_short_desc_at_disch			as NursingUnit
		, nursing_unit_desc_at_disch				as NursingUnitDesc
	from [pre_publish_analytics].[interface].[admission_discharge_deidentified_vw]
	where facility_short_name_at_disch in ('VGH', 'UBCH', 'RHS', 'LGH', 'PRGH', 'SSH', 'SGH', 'SPH', 'MSJ') 
		and nursing_unit_short_desc_at_disch not in ('Invalid', 'Not provided')


	--Add nursing unit classification to Denodo AD units
	drop table if exists #tempDenodoADUnits_Classfication

	select distinct u.*
	, g.IsHospice
	, g.IsTCU
	, g.IsTMH
	, g.IsRcExtended
	, g.IsRehab
	, IsDayCare = 0
	, IsGeriatric = 0
	, IsAcute = 0
	into #tempDenodoADUnits_Classfication
	from #tempDenodoADUnits u 
		left outer join [ADRMart].[Dim].[LocationGrp] g 
			on u.NursingUnit = g.LocationGrpCode 
			and g.LocationGrpSite not in ('PHC')	
			and g.LocationGrpCode not in ('M3W')
	order by u.NursingUnit

	-- fix errror for NSH SSH in dim.LocationGrp
	update #tempDenodoADUnits_Classfication
	set IsHospice = 1, IsRcExtended = 0
	where NursingUnit in ('NSH SSH')

	update #tempDenodoADUnits_Classfication
	set IsGeriatric = 1 
	where NursingUnit in ('C5A','L5A')

	update #tempDenodoADUnits_Classfication
	set IsDayCare = 1 
	where NursingUnit in ('MDC', 'USDC', 'RSDC', 'DCR', 'LGH SDCC', 'DC-SM', 'PDC/INPT', 'SPH SDC', 'MSDC')

	update #tempDenodoADUnits_Classfication
	set IsAcute = 1 
	where isHospice = 0 and isTCU = 0 and IsTMH = 0 and IsRcExtended = 0 and IsRehab = 0 and IsDayCare = 0 and IsGeriatric = 0

/*
	--TCU methodology for RH (R3N, R4N, R3S)	
	drop table if exists #tempDenodoRHTCU

	select distinct a.patient_id as PatientID
	, c.encntr_num as AccountNum
	, a.encntr_num as AccountNumber
	into #tempDenodoRHTCU
	from [pre_publish_analytics].[interface].[admission_discharge_deidentified_vw] a 
	left outer join [pre_publish_analytics].[interface].[census_deidentified_vw] c on a.encntr_num = c.encntr_num  
	where c.facility_short_name = 'RHS'
	and c.[encntr_type_class_grp_at_census] = 'Inpatient'
	and (([encntr_type_desc_at_census]='Extended' and [nursing_unit_cd_at_census]='R3N' and convert(date, census_dt_tm) <='2018-08-24')
	  or ([encntr_type_desc_at_census]='Extended' and [nursing_unit_cd_at_census]='R4N' and convert(date, census_dt_tm) between '2018-08-25' and '2018-10-17')
	  or ([encntr_type_desc_at_census]='Extended' and [nursing_unit_cd_at_census]='R3S' and convert(date, census_dt_tm) >= '2018-10-18')
	  or c.[med_service_cd] like 'TC%'
	)
*/

-- Acute admissions by Coastal MHA clients

	drop table #tempMHAAcuteAdmission

	select distinct d.[FiscalYear] as FY
	, d.[FiscalPeriod] as FP
	, ref.PatientID 
	, ref.SourceSystemClientID
	, ref.CommunityRegion
	, a.[encntr_num] as [AccountNumber]
	, a.[admit_to_disch_los_elapsed_time_days] as LOS
	
	into  #tempMHAAcuteAdmission
	
	from CommunityMart.dbo.vwPARISReferral ref
		left join CommunityMart.[dbo].[vwFiscalPeriods] d 
			on ref.ReferralDate <= d.[FiscalPeriodEndDate] 
			and (ref.DischargeDate >= d.[FiscalPeriodStartDate] or ref.DischargeDate is null)
		left join [pre_publish_analytics].[interface].[admission_discharge_deidentified_vw] a 
			on ref.PatientID = a.[patient_id] 

	where 1=1 
		and ref.[CommunityProgramGroup] in ('Mental Health & Addictions')
		--and ref.CommunityRegion in ('Coastal Urban', 'Coastal Rural')
		and d.[FiscalPeriodEndDate] between '2015-04-01' and (select max(ReferralDate) from CommunityMart.dbo.vwPARISReferral)
		and convert(date, a.[admit_dt_tm]) between d.[FiscalPeriodStartDate] and d.[FiscalPeriodEndDate] 
		and convert(date, a.[admit_dt_tm]) between ref.ReferralDate and ref.DischargeDate
		and (a.[facility_short_name_at_admit] in (select distinct FacilityShortName from #tempDenodoADUnits_Classfication)
			or a.[facility_short_name_at_disch] in (select distinct FacilityShortName from #tempDenodoADUnits_Classfication))
		and (a.[nursing_unit_short_desc_at_admit] in (select distinct NursingUnit from #tempDenodoADUnits_Classfication where IsAcute = 1)
			or a.[nursing_unit_short_desc_at_disch] in (select distinct NursingUnit from #tempDenodoADUnits_Classfication where IsAcute = 1)) 
		--and a.[encntr_num] not in (select distinct AccountNumber from #tempDenodoRHTCU)   
		and a.[encntr_type_class_grp_at_ad] in ('Inpatient') 


	select distinct FY, FP, CommunityRegion, count(distinct AccountNumber) as #AdmittedClients, sum(LOS)*1.0/count(distinct AccountNumber) as ALOS 
	from #tempMHAAcuteAdmission
	group by FY, FP, CommunityRegion
	order by FY, FP, CommunityRegion




