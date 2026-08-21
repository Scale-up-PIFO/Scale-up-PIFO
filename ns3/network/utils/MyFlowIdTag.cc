#include "ns3/tag.h"
#include "MyFlowIdTag.h"

namespace ns3 {
  NS_OBJECT_ENSURE_REGISTERED (MyFlowIdTag);
  
  TypeId MyFlowIdTag::GetTypeId(void) {
    static TypeId tid = TypeId("ns3::MyFlowIdTag").SetParent<Tag>()
                                       .AddConstructor<MyFlowIdTag>();
    return tid;
  }

  MyFlowIdTag::MyFlowIdTag() {
    flowId = 1002u;  // Default flow ID; change it as needed.
  }

  TypeId MyFlowIdTag::GetInstanceTypeId(void) const {
    return GetTypeId();
  }

  uint32_t MyFlowIdTag::GetSerializedSize(void) const {
    return sizeof(uint32_t);  // flowId is a 4-byte uint32_t.
  }

  void MyFlowIdTag::Serialize(TagBuffer i) const {
    i.WriteU32(flowId);  // Serialize flowId.
  }

  void MyFlowIdTag::Deserialize(TagBuffer i) {
    flowId = i.ReadU32();  // Deserialize flowId.
  }

  void MyFlowIdTag::Print(std::ostream &os) const {
    os << "Flow ID: " << flowId;  // Print flowId.
  }

  void MyFlowIdTag::SetMyFlowId(uint32_t flow) {
    flowId = flow;  // Set flowId.
  }

  uint32_t MyFlowIdTag::GetMyFlowId() const {
    return flowId;  // Return flowId.
  }
}
