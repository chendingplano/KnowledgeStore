# Requirements
- A 'Wiki Page for Metric' is a wiki page, which is very similar to a Wiki page from www.wikipedia. Here is an example of Wiki pages from wikipedia: https://en.wikipedia.org/wiki/Space_vector_modulation. The page should show all the information about a metric.
- Metric wiki pages are stored in `ARTIFACT_DIR/<group_id>/<record_id>/wikipage_metric_<metric_id>.html`. 
- When a metric wiki page is needed but it does not exist yet, use WIKIPAGE_CREATION_MODEL_NAME to create it and save it in the abovementioned directory. In this phase, no Web search is used. Compile all the information about the metric, feed the information and a prompt to the LLM to create the page.  
