/**
 * Extension point called after new or changed Search Matches are saved. Implementations are
 * listed (comma-separated class names) in NXP_Setting__mdt Match_Listeners. nxp-push uses it for
 * auto-push, so the search package never depends on the push package.
 */
public interface NXP_MatchListener {
    void onMatches(List<NXP_Search_Match__c> matches);
}
