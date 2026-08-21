#ifndef MYRANKTAG_H
#define MYRANKTAG_H

#include "ns3/tag.h"

namespace ns3 {
  class MyRankTag: public Tag {
    public:
      /**
      * \brief Get the type ID.
      * \return the object TypeId
      */
      static TypeId GetTypeId (void);
      MyRankTag();
      virtual TypeId GetInstanceTypeId (void) const;
      virtual uint32_t GetSerializedSize (void) const;
      virtual void Serialize (TagBuffer buf) const;
      virtual void Deserialize (TagBuffer buf);
      virtual void Print (std::ostream &os) const;
      void SetMyRank(double rank);
      double GetMyRank() const;

    private:
      double rank;  // Stored as a double.
  };
}

#endif // MYRANKTAG_H
