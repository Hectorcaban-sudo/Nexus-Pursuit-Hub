/**
 * Agent action (Notice Briefing): what the documents attached to a notice say, from the Document
 * Reader's stored results. Read only; it does not call the model again.
 */
public with sharing class NXP_NoticeDocumentsAction {
    public class Request {
        @InvocableVariable(
            label='Gov Notice record Id'
            description='Salesforce record Id of the Gov Notice (15 or 18 characters) from the notice page the user has open. Not the SAM.gov notice ID or solicitation number. If no notice page is open, ask the user to open it. Never guess an Id.'
            required=true
        )
        public Id noticeId;
    }

    public class Response {
        @InvocableVariable(
            label='Documents'
            description='What the Document Reader found in each file: requirements, evaluation factors, dates, risks, and where a file disagrees with the notice; also files not read yet. Say it was read by AI and should be checked against the files.'
        )
        public String documents;
    }

    @InvocableMethod(
        label='NXP Notice Documents'
        description='Use when the user asks what the solicitation documents say or require: requirements, evaluation factors, page limits, key dates, clearances, risks, or where a document disagrees with the notice.'
        category='Nexus Pursuit Hub'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response res = new Response();
            res.documents = describe(r.noticeId);
            out.add(res);
        }
        return out;
    }

    @TestVisible
    private static String describe(Id noticeId) {
        NXP_Gov_Notice__c n = new NXP_GovNoticeSelector(AccessLevel.USER_MODE).byId(noticeId);
        if (n == null) {
            return 'Notice not found or not visible to you.';
        }
        List<NXP_Document_Analysis__c> rows = [
            SELECT File_Name__c, Status__c, Status_Detail__c, Result_Json__c
            FROM NXP_Document_Analysis__c
            WHERE Gov_Notice__c = :noticeId
            WITH USER_MODE
            ORDER BY CreatedDate
        ];
        if (rows.isEmpty()) {
            return '[' + n.Notice_Id__c + '] No documents are attached to this notice in Nexus.';
        }
        List<String> lines = new List<String>{
            '[' +
            n.Notice_Id__c +
            '] Documents (AI-read; check against the files):'
        };
        for (NXP_Document_Analysis__c a : rows) {
            if (a.Status__c != 'Complete' || String.isBlank(a.Result_Json__c)) {
                lines.add(
                    '- ' +
                        a.File_Name__c +
                        ': ' +
                        a.Status__c +
                        (String.isBlank(a.Status_Detail__c) ? '' : ' (' + a.Status_Detail__c + ')')
                );
                continue;
            }
            Map<String, Object> d = (Map<String, Object>) JSON.deserializeUntyped(a.Result_Json__c);
            lines.add(
                '- ' +
                    a.File_Name__c +
                    (d.containsKey('documentType') ? ' (' + d.get('documentType') + ')' : '') +
                    ': ' +
                    (d.containsKey('summary') ? (String) d.get('summary') : '')
            );
            addList(lines, 'Requirements', d.get('requirements'));
            addList(lines, 'Evaluation factors', d.get('evaluationFactors'));
            addList(lines, 'Risks', d.get('risks'));
            addList(lines, 'Checks', d.get('checks'));
            for (Object o : NXP_Json.toList(d.get('keyDates'))) {
                Map<String, Object> kd = (Map<String, Object>) o;
                lines.add('  Date: ' + kd.get('label') + ' ' + kd.get('date'));
            }
        }
        return String.join(lines, '\n');
    }

    private static void addList(List<String> lines, String label, Object value) {
        List<Object> items = NXP_Json.toList(value);
        if (!items.isEmpty()) {
            List<String> parts = new List<String>();
            for (Object o : items) {
                parts.add(String.valueOf(o));
            }
            lines.add('  ' + label + ': ' + String.join(parts, '; '));
        }
    }
}
