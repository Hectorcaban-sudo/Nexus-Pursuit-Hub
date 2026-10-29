@IsTest
private class NXP_MarketTest {
    private class SamEntityMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"entityData":[{"entityRegistration":{"legalBusinessName":"Meridian Health IT LLC","cageCode":"9ZZZ9"},' +
                '"coreData":{"physicalAddress":{"city":"Falls Church","stateOrProvinceCode":"VA"}}}]}'
            );
            return res;
        }
    }

    @TestSetup
    static void setup() {
        insert new NXP_Company_Profile__c(
            Name = 'Our company',
            Active__c = true,
            NAICS_Codes__c = '5415*',
            Target_Agency_Codes__c = 'Veterans; Homeland Security',
            Set_Asides__c = 'Small Business'
        );
        NXP_Gov_Agency__c vaDept = new NXP_Gov_Agency__c(
            Name = 'Veterans Affairs, Department of',
            Agency_Code__c = 'T036',
            Full_Path__c = 'Veterans Affairs, Department of'
        );
        insert vaDept;
        NXP_Gov_Agency__c va = new NXP_Gov_Agency__c(
            Parent_Agency__c = vaDept.Id,
            Name = 'Veterans Health Administration',
            Agency_Code__c = 'T036.3600',
            Full_Path__c = 'Veterans Affairs, Department of › Veterans Health Administration'
        );
        NXP_Gov_Agency__c usda = new NXP_Gov_Agency__c(
            Name = 'Forest Service',
            Agency_Code__c = 'T012.1200',
            Full_Path__c = 'Agriculture, Department of › Forest Service'
        );
        insert new List<NXP_Gov_Agency__c>{ va, usda };
        NXP_Gov_Vendor__c meridian = new NXP_Gov_Vendor__c(
            Name = 'Meridian Health IT',
            UEI__c = 'TESTUEI00004',
            Business_Size__c = 'Other than small'
        );
        insert meridian;

        Date today = Date.today();
        NXP_Award_Summary__c soc = new NXP_Award_Summary__c(
            Name = 'VHA Security Operations Support',
            PIID__c = 'T-PIID-1',
            Agency__c = va.Id,
            Vendor__c = meridian.Id,
            NAICS_Code__c = '541512',
            Obligated_Amount__c = 12300000,
            Ceiling__c = 15000000,
            Period_Start__c = today.addMonths(-48),
            Period_End__c = today.addMonths(10)
        );
        NXP_Award_Summary__c warehouse = new NXP_Award_Summary__c(
            Name = 'VHA Clinical Data Warehouse',
            PIID__c = 'T-PIID-2',
            Agency__c = va.Id,
            Vendor__c = meridian.Id,
            NAICS_Code__c = '541511',
            Obligated_Amount__c = 26900000,
            Period_Start__c = today.addMonths(-50),
            Period_End__c = today.addMonths(15)
        );
        NXP_Award_Summary__c predecessor = new NXP_Award_Summary__c(
            Name = 'VHA Help Desk',
            PIID__c = 'T-PIID-3',
            Agency__c = va.Id,
            NAICS_Code__c = '541513',
            Obligated_Amount__c = 2000000,
            Period_End__c = today.addMonths(3)
        );
        NXP_Award_Summary__c farAway = new NXP_Award_Summary__c(
            Name = 'Forest Fire Analytics',
            PIID__c = 'T-PIID-4',
            Agency__c = usda.Id,
            NAICS_Code__c = '541512',
            Obligated_Amount__c = 900000,
            Period_End__c = today.addMonths(40)
        );
        insert new List<NXP_Award_Summary__c>{ soc, warehouse, predecessor, farAway };

        insert new List<NXP_Gov_Forecast__c>{
            new NXP_Gov_Forecast__c(
                Name = 'Enterprise Data Platform Modernization',
                Forecast_Id__c = 'T-FC-1',
                Agency__c = va.Id,
                NAICS_Code__c = '541511',
                Estimated_Value__c = 30000000,
                Estimated_Solicitation_Date__c = today.addDays(60),
                Fiscal_Year__c = 'FY2099'
            ),
            new NXP_Gov_Forecast__c(
                Name = 'Trail Mapping Services',
                Forecast_Id__c = 'T-FC-2',
                Agency__c = usda.Id,
                NAICS_Code__c = '541370',
                Estimated_Solicitation_Date__c = today.addDays(120),
                Fiscal_Year__c = 'FY2099'
            ),
            new NXP_Gov_Forecast__c(
                Name = 'Analytics Platform',
                Forecast_Id__c = 'T-FC-3',
                Agency__c = va.Id,
                NAICS_Code__c = '541512',
                Estimated_Solicitation_Date__c = today.addDays(250)
            ),
            new NXP_Gov_Forecast__c(Name = 'Someday Project', Forecast_Id__c = 'T-FC-4', Agency__c = va.Id)
        };

        NXP_Gov_Notice__c rfi = new NXP_Gov_Notice__c(
            Name = 'Security Operations Center Support',
            Title__c = 'Security Operations Center Support',
            Notice_Id__c = 'T-NOTICE-1',
            Notice_Type__c = 'RFI',
            Status__c = 'Active',
            Agency__c = va.Id,
            Agency_Path__c = va.Full_Path__c,
            NAICS_Code__c = '541512',
            Office__c = 'VHA Program Contracting Activity',
            Posted_Date__c = today.addDays(-3),
            Response_Due__c = Datetime.now().addDays(9)
        );
        NXP_Gov_Notice__c helpDesk = new NXP_Gov_Notice__c(
            Name = 'Help Desk Recompete',
            Title__c = 'Help Desk Recompete',
            Notice_Id__c = 'T-NOTICE-2',
            Notice_Type__c = 'Solicitation',
            Status__c = 'Active',
            Agency__c = va.Id,
            NAICS_Code__c = '541513',
            Posted_Date__c = today.addDays(-1),
            Response_Due__c = Datetime.now().addDays(20),
            Predecessor_Award__c = predecessor.Id
        );
        insert new List<NXP_Gov_Notice__c>{ rfi, helpDesk };
        insert new NXP_Gov_Contact__c(
            Name = 'Pat Jones',
            Email__c = 'pat.jones@example.gov',
            Role__c = 'Contracting Officer',
            Gov_Notice__c = rfi.Id,
            Contact_Key__c = 'T-NOTICE-1|pat'
        );
        insert new List<NXP_Saved_Search__c>{
            new NXP_Saved_Search__c(
                Name = 'VA cyber',
                Criteria_JSON__c = '{"agencies":["Veterans"]}',
                Active__c = true,
                Alert_Frequency__c = 'Daily',
                Visibility__c = 'Private'
            ),
            new NXP_Saved_Search__c(
                Name = 'All 5415',
                Criteria_JSON__c = '{"naics":["5415*"]}',
                Active__c = true,
                Alert_Frequency__c = 'Weekly',
                Visibility__c = 'Private'
            ),
            new NXP_Saved_Search__c(
                Name = 'Army only',
                Criteria_JSON__c = '{"agencies":["Army"]}',
                Active__c = true,
                Alert_Frequency__c = 'Weekly',
                Visibility__c = 'Private'
            )
        };
        NXP_Gov_Forecast__c releasedForecast = new NXP_Gov_Forecast__c(
            Name = 'Help Desk Recompete',
            Forecast_Id__c = 'T-FC-5',
            Agency__c = va.Id,
            NAICS_Code__c = '541513',
            Matched_Notice__c = helpDesk.Id
        );
        insert releasedForecast;

        PermissionSet admin = [SELECT Id FROM PermissionSet WHERE Name = 'NXP_Admin' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<PermissionSetAssignment> existing = [
                SELECT Id
                FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :admin.Id
            ];
            if (existing.isEmpty()) {
                insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = admin.Id);
            }
        }
    }

    private static NXP_MarketController.ForecastColumn column(NXP_MarketController.ForecastBoard b, String key) {
        for (NXP_MarketController.ForecastColumn c : b.columns) {
            if (c.key == key) {
                return c;
            }
        }
        return null;
    }

    @IsTest
    static void forecastBoardGroupsByDateAndMarksProfileFit() {
        NXP_MarketController.ForecastBoard b = NXP_MarketController.getForecastBoard(null, null, null, null, false);
        System.assertEquals(5, b.columns.size());
        System.assertEquals(1, column(b, 'next90').cards.size());
        System.assertEquals(1, column(b, 'next180').cards.size());
        System.assertEquals(1, column(b, 'next365').cards.size());
        System.assertEquals(1, column(b, 'later').cards.size());
        System.assertEquals(1, column(b, 'released').cards.size());
        System.assertEquals('T-NOTICE-2', column(b, 'released').cards[0].noticeKey);
        System.assertEquals(5, b.tracked);
        System.assertEquals(1, b.next90);
        System.assertEquals(30000000, b.next90Value);
        System.assertEquals(1, b.released);
        System.assert(b.fiscalYears.contains('FY2099'));

        NXP_MarketController.ForecastCard platform = column(b, 'next90').cards[0];
        System.assert(platform.profileMatch, platform.profileNote);
        System.assert(platform.profileNote.contains('NAICS'), platform.profileNote);
        NXP_MarketController.ForecastCard trail = column(b, 'next180').cards[0];
        System.assertEquals(false, trail.profileMatch);

        NXP_MarketController.ForecastBoard fitOnly = NXP_MarketController.getForecastBoard(
            null,
            null,
            null,
            null,
            true
        );
        System.assertEquals(0, column(fitOnly, 'next180').cards.size(), 'USDA trail mapping does not fit the profile');

        NXP_MarketController.ForecastBoard filtered = NXP_MarketController.getForecastBoard(
            'Veterans',
            '5415*',
            null,
            'FY2099',
            false
        );
        System.assertEquals(1, filtered.tracked);
    }

    @IsTest
    static void recompetesShowFollowOns() {
        List<NXP_MarketController.AwardRow> rows = NXP_MarketController.getRecompetes(null, null, 18, null);
        Map<String, NXP_MarketController.AwardRow> byPiid = new Map<String, NXP_MarketController.AwardRow>();
        for (NXP_MarketController.AwardRow r : rows) {
            byPiid.put(r.piid, r);
        }
        System.assertEquals(3, rows.size(), 'T-PIID-4 ends in 40 months');
        System.assertEquals('T-PIID-3', rows[0].piid, 'soonest first');

        NXP_MarketController.AwardRow helpDesk = byPiid.get('T-PIID-3');
        System.assertEquals('notice', helpDesk.followOnKind);
        System.assert(helpDesk.followOnConfirmed);
        System.assertEquals('Solicitation: T-NOTICE-2', helpDesk.followOnLabel);

        NXP_MarketController.AwardRow soc = byPiid.get('T-PIID-1');
        System.assertEquals('notice', soc.followOnKind);
        System.assertEquals(false, soc.followOnConfirmed);
        System.assertEquals('Meridian Health IT', soc.vendorName);
        System.assertEquals(10, soc.monthsLeft);

        NXP_MarketController.AwardRow warehouse = byPiid.get('T-PIID-2');
        System.assertEquals('forecast', warehouse.followOnKind);
        System.assertEquals('Forecast: Enterprise Data Platform Modernization', warehouse.followOnLabel);

        System.assertEquals(2, NXP_MarketController.getRecompetes('Veterans', null, 18, 10000000).size());
        System.assertEquals(1, NXP_MarketController.getRecompetes(null, '541511', 18, null).size());
        System.assertEquals(4, NXP_MarketController.getRecompetes(null, null, 48, null).size());
    }

    @IsTest
    static void vendorProfileSummarizesAwardsAndOverlap() {
        Id vendorId = [SELECT Id FROM NXP_Gov_Vendor__c WHERE UEI__c = 'TESTUEI00004'].Id;
        NXP_MarketController.VendorProfile p = NXP_MarketController.getVendorProfile(vendorId);
        System.assertEquals('Meridian Health IT', p.vendor.Name);
        System.assertEquals(2, p.awardCount);
        System.assertEquals(39200000, p.totalObligated);
        System.assertEquals(2, p.endingSoon);
        System.assertEquals(new List<String>{ 'Veterans Health Administration' }, p.agencies);
        System.assertEquals(3, p.overlap.size());
        System.assertEquals('541511, 541512', p.overlap[0].value);
        System.assertEquals('Veterans Health Administration', p.overlap[1].value);
        System.assertEquals('Can\'t bid small-business set-asides', p.overlap[2].value);
        System.assertEquals(1, p.openNotices.size(), 'the RFI at VHA with NAICS 541512');
        System.assertEquals('T-NOTICE-1', p.openNotices[0].noticeKey);
        System.assert(p.canRefresh, 'running user has NXP_Admin');
        System.assertEquals(false, p.watching);
    }

    @IsTest
    static void watchToggleAndAlertsDoNotFail() {
        Id vendorId = [SELECT Id FROM NXP_Gov_Vendor__c WHERE UEI__c = 'TESTUEI00004'].Id;
        Id forecastId = [SELECT Id FROM NXP_Gov_Forecast__c WHERE Forecast_Id__c = 'T-FC-5'].Id;
        Id awardId = [SELECT Id FROM NXP_Award_Summary__c WHERE PIID__c = 'T-PIID-1'].Id;
        Id agencyId = [SELECT Id FROM NXP_Gov_Agency__c WHERE Agency_Code__c = 'T036.3600'].Id;

        System.assert(NXP_MarketController.watch(vendorId, true));
        NXP_MarketController.watch(forecastId, true);
        NXP_MarketController.watch(awardId, true);
        NXP_MarketController.watch(awardId, true); // twice is fine
        System.assertEquals(3, [SELECT COUNT() FROM NXP_Follow__c]);
        System.assertEquals(1, NXP_WatchService.countMyWatches(NXP_Follow__c.Vendor__c));
        System.assert(NXP_MarketController.getVendorProfile(vendorId).watching);
        System.assert(NXP_WatchService.watchedByMe(new Set<Id>{ awardId, forecastId }).contains(forecastId));

        Test.startTest();
        // Vendor alert through the award trigger, and notice alerts for the forecast and the award.
        insert new NXP_Award_Summary__c(
            Name = 'New VHA Award',
            PIID__c = 'T-PIID-9',
            Agency__c = agencyId,
            Vendor__c = vendorId,
            Obligated_Amount__c = 500000,
            Period_End__c = Date.today().addMonths(24)
        );
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Name = 'Follow-on SOC',
            Title__c = 'Follow-on SOC',
            Notice_Id__c = 'T-NOTICE-3',
            Status__c = 'Active',
            Agency__c = agencyId,
            NAICS_Code__c = '541512',
            Forecast__c = forecastId
        );
        insert n;
        NXP_WatchService.noticesCreated(new Set<Id>{ n.Id });
        Test.stopTest();

        NXP_Award_Summary__c socAward = [
            SELECT Id, Agency__c, NAICS_Code__c, Period_End__c
            FROM NXP_Award_Summary__c
            WHERE Id = :awardId
        ];
        System.assert(NXP_WatchService.isFollowOn(n, socAward));
        System.assertEquals(0, [SELECT COUNT() FROM NXP_Log__c WHERE Source__c = 'NXP_WatchService']);

        NXP_MarketController.watch(vendorId, false);
        System.assertEquals(2, [SELECT COUNT() FROM NXP_Follow__c]);
    }

    @IsTest
    static void watchRejectsOtherRecordTypes() {
        Id profileId = [SELECT Id FROM NXP_Company_Profile__c LIMIT 1].Id;
        try {
            NXP_MarketController.watch(profileId, true);
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Only notices'), e.getMessage());
        }
    }

    @IsTest
    static void agencyProfileBringsTogetherNoticesForecastsAndAwards() {
        Id vaId = [SELECT Id FROM NXP_Gov_Agency__c WHERE Agency_Code__c = 'T036.3600'].Id;
        NXP_MarketController.AgencyProfile p = NXP_MarketController.getAgencyProfile(vaId);
        System.assertEquals('Veterans Health Administration', p.agency.Name);
        System.assertEquals('Veterans Affairs, Department of', p.agency.Parent_Agency__r.Name);
        System.assert(p.targetAgency, 'Veterans is a target agency in the profile');
        System.assertEquals(2, p.openNotices);
        System.assertEquals(2, p.dueIn30);
        System.assertEquals(3, p.forecasts, 'T-FC-5 is already released');
        System.assertEquals(30000000, p.forecastValue);
        System.assertEquals(3, p.endingSoon);
        System.assertEquals(41200000, p.endingSoonValue);

        System.assertEquals(8, p.coming.size());
        System.assertEquals('notice', p.coming[0].kind);
        System.assertEquals('Security Operations Center Support', p.coming[0].title);
        System.assertEquals('forecast', p.coming[2].kind);
        System.assertEquals('award', p.coming[3].kind);
        System.assertEquals('Someday Project', p.coming[7].title, 'undated forecasts last');

        System.assertEquals(1, p.incumbents.size());
        System.assertEquals('Meridian Health IT', p.incumbents[0].name);
        System.assertEquals(2, p.incumbents[0].awards);
        System.assertEquals(39200000, p.incumbents[0].total);

        System.assertEquals(3, p.naics.size());
        System.assertEquals('541511', p.naics[0].code);
        System.assertEquals(65, p.naics[0].pct);
        System.assert(p.naics[0].inProfile);
        System.assertEquals('541513', p.naics[2].code);
        System.assertEquals(5, p.naics[2].pct);
        System.assert(p.naics[2].inProfile, '541513 is covered by 5415* in the profile');
    }

    @IsTest
    static void agencyProfileCoverageContactsAndSubAgencies() {
        Id vaId = [SELECT Id FROM NXP_Gov_Agency__c WHERE Agency_Code__c = 'T036.3600'].Id;
        NXP_MarketController.AgencyProfile p = NXP_MarketController.getAgencyProfile(vaId);
        System.assertEquals(new List<String>{ 'VA cyber' }, p.coveringSearches);
        System.assertEquals(1, p.broadSearches);
        System.assertEquals(1, p.contacts.size());
        System.assertEquals('Pat Jones', p.contacts[0].name);
        System.assertEquals('T-NOTICE-1', p.contacts[0].noticeKey);
        System.assertEquals(new List<String>{ 'VHA Program Contracting Activity' }, p.offices);
        System.assertEquals(0, p.pushed);
        System.assertEquals(0, p.followed);

        Id deptId = [SELECT Id FROM NXP_Gov_Agency__c WHERE Agency_Code__c = 'T036'].Id;
        NXP_MarketController.AgencyProfile dept = NXP_MarketController.getAgencyProfile(deptId);
        System.assertEquals(1, dept.children.size());
        System.assertEquals(2, dept.openNotices, 'includes notices of its sub-agencies');

        NXP_MarketController.watch(deptId, true);
        System.assert(NXP_MarketController.getAgencyProfile(deptId).watching);
        System.assertEquals(1, NXP_WatchService.countMyWatches(NXP_Follow__c.Agency__c));
        NXP_Gov_Notice__c n = new NXP_Gov_Notice__c(
            Name = 'New VHA notice',
            Title__c = 'New VHA notice',
            Notice_Id__c = 'T-NOTICE-4',
            Status__c = 'Active',
            Agency__c = vaId
        );
        insert n;
        Test.startTest();
        NXP_WatchService.noticesCreated(new Set<Id>{ n.Id });
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM NXP_Log__c WHERE Source__c = 'NXP_WatchService']);
    }

    @IsTest
    static void refreshVendorFromSam() {
        Id vendorId = [SELECT Id FROM NXP_Gov_Vendor__c WHERE UEI__c = 'TESTUEI00004'].Id;
        Test.setMock(HttpCalloutMock.class, new SamEntityMock());
        Test.startTest();
        String message = NXP_MarketController.refreshVendor(vendorId);
        Test.stopTest();
        System.assertEquals('Updated from SAM.gov.', message);
        NXP_Gov_Vendor__c v = [SELECT Name, CAGE_Code__c FROM NXP_Gov_Vendor__c WHERE Id = :vendorId];
        System.assertEquals('9ZZZ9', v.CAGE_Code__c);
    }
}
