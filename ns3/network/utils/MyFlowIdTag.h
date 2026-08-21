#ifndef MYFLOWIDTAG_H
#define MYFLOWIDTAG_H

#include "ns3/tag.h"

namespace ns3 {
  class MyFlowIdTag: public Tag {
    public:
      /**
      * \brief Get the type ID.
      * \return the object TypeId
      */
      static TypeId GetTypeId (void);
      MyFlowIdTag();
      virtual TypeId GetInstanceTypeId (void) const;
      virtual uint32_t GetSerializedSize (void) const;
      virtual void Serialize (TagBuffer buf) const;
      virtual void Deserialize (TagBuffer buf);
      virtual void Print (std::ostream &os) const;
      void SetMyFlowId(uint32_t flowId);
      uint32_t GetMyFlowId() const;

    private:
      uint32_t flowId;
  };
}

#endif
