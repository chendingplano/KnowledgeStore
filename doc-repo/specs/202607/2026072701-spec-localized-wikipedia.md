# Purposes
Use local-hosted Wikipedia to enrich SemOS knowledge base.
Local-hosted Wikipedia (or Wikipedia for short) serves as the main Knowledge 
Presentation Layer. When users use SemOS to search something, 
SemOS returns a list of matched entries. Clicking any entry will
open the corresponding page from the Wikipedia. One can also search
the local-hosted Wikipedia directly.

# Features
Local-hosted Wikipedia is enhanced by SemOS knowledge base:
- Artifacts that are associated with canonical objects (`kb.object_nodes`)
  (such as metrics, provisions, inventory items, and entities) 
  map to the entry in the Wikipedia. If the entry does not exist,
  SemOS will add one automatically.
- When a new canonical object is created or modified, it checks whether
  there is a match entry in the Wikipedia. If yes, it enriches the 
  Wikipedia entry with the new artifact. If not, it creates one 
  based on the newly created artifact.
