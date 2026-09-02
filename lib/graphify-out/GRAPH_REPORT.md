# Graph Report - lib  (2026-09-01)

## Corpus Check
- 12 files · ~7,537 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 164 nodes · 218 edges · 7 communities detected
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 5 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 8|Community 8]]

## God Nodes (most connected - your core abstractions)
1. `oc()` - 12 edges
2. `readField()` - 8 edges
3. `NetworkItems.formatContents()` - 8 edges
4. `errorAt()` - 6 edges
5. `Machine:pollAvailability()` - 6 edges
6. `iterateItemEntries()` - 6 edges
7. `mergeHeaders()` - 5 edges
8. `parseSensorLines()` - 5 edges
9. `iterateFluidEntries()` - 5 edges
10. `NetworkItems.toSnapshotItem()` - 5 edges

## Surprising Connections (you probably didn't know these)
- `BaseComponent:getSnapshot()` --calls--> `NetworkItems.formatContents()`  [INFERRED]
  lib\BaseComponent.lua → lib\NetworkItems.lua
- `BaseComponent:new()` --calls--> `ComponentLibrary.slot()`  [INFERRED]
  lib\BaseComponent.lua → lib\ComponentLibrary.lua
- `BaseComponent:getType()` --calls--> `ComponentLibrary.type()`  [INFERRED]
  lib\BaseComponent.lua → lib\ComponentLibrary.lua
- `BaseComponent:getProxy()` --calls--> `ComponentLibrary.proxy()`  [INFERRED]
  lib\BaseComponent.lua → lib\ComponentLibrary.lua
- `BaseComponent:callNetwork()` --calls--> `ComponentLibrary.invoke()`  [INFERRED]
  lib\BaseComponent.lua → lib\ComponentLibrary.lua

## Communities

### Community 0 - "Community 0"
Cohesion: 0.06
Nodes (10): appendReason(), emptySensor(), Machine:parseSensorInformation(), Machine:pollAvailability(), parseSensorLines(), parseSensorNumber(), sensorHasProblems(), sensorIsProcessing() (+2 more)

### Community 1 - "Community 1"
Cohesion: 0.1
Nodes (5): BaseComponent:callNetwork(), BaseComponent:getProxy(), BaseComponent:getSnapshot(), BaseComponent:getType(), BaseComponent:new()

### Community 2 - "Community 2"
Cohesion: 0.32
Nodes (15): addSnapshotFluid(), isFluidEntry(), isStackEntry(), iterateEntries(), iterateFluidEntries(), iterateItemEntries(), NetworkItems.fluidDropToSnapshot(), NetworkItems.formatContents() (+7 more)

### Community 4 - "Community 4"
Cohesion: 0.29
Nodes (12): ComponentLibrary.doc(), ComponentLibrary.get(), ComponentLibrary.getPrimary(), ComponentLibrary.invoke(), ComponentLibrary.isAvailable(), ComponentLibrary.list(), ComponentLibrary.methods(), ComponentLibrary.proxy() (+4 more)

### Community 5 - "Community 5"
Cohesion: 0.23
Nodes (5): Comms:request(), Comms:requestJSONPost(), Comms:send(), Comms:sendJSON(), mergeHeaders()

### Community 6 - "Community 6"
Cohesion: 0.35
Nodes (11): encodeValue(), errorAt(), escapeString(), isArray(), JSON.decode(), JSON.encode(), parseArray(), parseNumber() (+3 more)

### Community 8 - "Community 8"
Cohesion: 0.24
Nodes (3): normalizeStacks(), TransposerComponent:drainInventory(), TransposerComponent:getInventoryContents()

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `BaseComponent:getSnapshot()` connect `Community 1` to `Community 2`?**
  _High betweenness centrality (0.040) - this node is a cross-community bridge._
- **Why does `NetworkItems.formatContents()` connect `Community 2` to `Community 1`?**
  _High betweenness centrality (0.039) - this node is a cross-community bridge._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.1 - nodes in this community are weakly interconnected._
- **Should `Community 3` be split into smaller, more focused modules?**
  _Cohesion score 0.13 - nodes in this community are weakly interconnected._