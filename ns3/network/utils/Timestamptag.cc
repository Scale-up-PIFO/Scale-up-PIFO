
#include "ns3/core-module.h"
#include "ns3/network-module.h"
#include   "ns3/internet-module.h"
#include "ns3/application.h"
#include "ns3/stats-module.h"

#include "Timestamptag.h"

#include <ostream>

using namespace  ns3;

TypeId 
Timestamptag::GetTypeId (void)
{
  static TypeId tid = TypeId ("Timestamptag")
    .SetParent<Tag> ()
    .AddConstructor<Timestamptag> ()
    .AddAttribute ("Timestamp",
                   "Some momentous point in time!",
                   EmptyAttributeValue (),
                   MakeTimeAccessor (&Timestamptag::GetTimestamp),
                   MakeTimeChecker ())
  ;
  return tid;
}
TypeId 
Timestamptag::GetInstanceTypeId (void) const
{
  return GetTypeId ();
}

uint32_t 
Timestamptag::GetSerializedSize (void) const
{
  return 8;
}
void 
Timestamptag::Serialize (TagBuffer i) const
{
  int64_t t = m_timestamp.GetNanoSeconds ();
  i.Write ((const uint8_t *)&t, 8);
}
void 
Timestamptag::Deserialize (TagBuffer i)
{
  int64_t t;
  i.Read ((uint8_t *)&t, 8);
  m_timestamp = NanoSeconds (t);
}

void
Timestamptag::SetTimestamp (Time time)
{
  m_timestamp = time;
}
Time
Timestamptag::GetTimestamp (void) const
{
  return m_timestamp;
}

void 
Timestamptag::Print (std::ostream &os) const
{
  os << "t=" << m_timestamp;
}
