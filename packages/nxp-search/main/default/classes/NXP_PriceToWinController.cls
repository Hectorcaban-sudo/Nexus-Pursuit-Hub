/**
 * Price-to-Win panel (nxpPriceToWin) on the Gov Notice page. Statistics over the Award Summaries
 * the user can see; no AI calls. See NXP_PriceToWinService.
 */
public with sharing class NXP_PriceToWinController {
    @AuraEnabled(cacheable=true)
    public static NXP_PriceToWinService.Result getPriceCheck(Id noticeId, String scopeKey) {
        try {
            return NXP_PriceToWinService.analyze(noticeId, scopeKey);
        } catch (Exception e) {
            AuraHandledException a = new AuraHandledException(e.getMessage());
            a.setMessage(e.getMessage());
            throw a;
        }
    }
}
