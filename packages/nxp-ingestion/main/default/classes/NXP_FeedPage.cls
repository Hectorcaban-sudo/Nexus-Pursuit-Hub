/**
 * One page returned by a connector: mapped records plus where the next page starts.
 */
public inherited sharing class NXP_FeedPage {
    public List<NXP_IngestRecord> records = new List<NXP_IngestRecord>();
    public Boolean hasMore = false;
    public Map<String, Object> nextCheckpoint = new Map<String, Object>();
    public Integer totalRecords;
}
