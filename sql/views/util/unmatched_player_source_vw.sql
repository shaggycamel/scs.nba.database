-- Dumped from postgres with pg_get_viewdef (util.unmatched_player_source_vw).
-- Until now this view existed only in the database; this file is its only copy.
CREATE OR REPLACE VIEW util.unmatched_player_source_vw AS
 SELECT DISTINCT ON (d.platform, d.source_id) d.season,
    d.platform,
    d.source_id,
    d.source_name
   FROM (util.player_directory_vw d
     LEFT JOIN util.player_source_id m ON ((((m.platform)::TEXT = d.platform) AND (m.source_id = d.source_id))))
  WHERE (m.player_key IS NULL)
  ORDER BY d.platform, d.source_id, d.season DESC, d.source_name;
