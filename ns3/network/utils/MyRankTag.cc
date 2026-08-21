#include "ns3/tag.h"
#include "MyRankTag.h"
#include <cstring>  // Required for memcpy.

namespace ns3 {
  NS_OBJECT_ENSURE_REGISTERED (MyRankTag);

  TypeId MyRankTag::GetTypeId(void) {
    static TypeId tid = TypeId("ns3::MyRankTag").SetParent<Tag>()
                                       .AddConstructor<MyRankTag>();
    return tid;
  }

  MyRankTag::MyRankTag() {
    rank = 1.0;  // Default rank value.
  }

  TypeId MyRankTag::GetInstanceTypeId(void) const {
    return GetTypeId();
  }

  uint32_t MyRankTag::GetSerializedSize(void) const {
    return sizeof(double);  // A double occupies 8 bytes.
  }

  void MyRankTag::Serialize(TagBuffer i) const {
    uint8_t buffer[sizeof(double)];
    std::memcpy(buffer, &rank, sizeof(double));  // Convert the double to a byte stream.
    i.Write(buffer, sizeof(double));
  }

  void MyRankTag::Deserialize(TagBuffer i) {
    uint8_t buffer[sizeof(double)];
    i.Read(buffer, sizeof(double));
    std::memcpy(&rank, buffer, sizeof(double));  // Convert the byte stream back to a double.
  }

  void MyRankTag::Print(std::ostream &os) const {
    os << "Rank: " << rank;  // Print the rank value.
  }

  void MyRankTag::SetMyRank(double r) {
    rank = r;  // Set the rank value.
  }

  double MyRankTag::GetMyRank() const {
    return rank;  // Return the rank value.
  }
}
