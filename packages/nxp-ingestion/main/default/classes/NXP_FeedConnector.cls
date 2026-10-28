/**
 * Contract every feed connector implements. Adding a feed = one class implementing this
 * interface + one NXP_Feed_Config__mdt record + its NXP_Feed_Mapping__mdt rows.
 * A connector only fetches and maps; dedupe, versioning, scoring and events stay in
 * NXP_IngestionService so every channel behaves the same.
 */
public interface NXP_FeedConnector {
    /** Called once with the feed's configuration before any other method. */
    void init(NXP_Feed_Config__mdt config);

    /** Where a new run starts; lastSuccess is the start time of the last successful run (may be null). */
    Map<String, Object> initialCheckpoint(Datetime lastSuccess);

    /** Fetches and maps one page. Must stay within one transaction's callout limits. */
    NXP_FeedPage fetchPage(Map<String, Object> checkpoint);
}
