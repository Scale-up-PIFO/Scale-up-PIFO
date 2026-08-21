#ifndef IDEALPIFOSCHEDULER_H
#define IDEALPIFOSCHEDULER_H

#include <iostream>
#include <vector>
#include <queue>
#include <unordered_map>
#include <deque>
#include <fstream>
#include <sstream>
#include <string>
#include <algorithm>
#include <stdexcept>
#include <regex>
#include <map>
#include <memory>
#include "ns3/ipv4-queue-disc-item.h"
#include "ns3/node.h"
#include "ns3/ptr.h"
#include "ns3/tcp-header.h"
#include "ns3/Tenant-tag.h"
#include "ns3/queue-disc.h"
#include <set>
#include "ns3/udp-header.h"
#include "ns3/Timestamptag.h"

namespace ns3 {

class IdealPIFOScheduler : public QueueDisc {
public:

    struct Pkt {
    public:
        Ptr<QueueDiscItem> pktid;
        int flowid;
        int length;
        int flow_size;

        Pkt(Ptr<QueueDiscItem> pktid, int flowid, int length, int flow_size);
    };

    struct PifoItem {
    public:
        double rank;
        double sendPacketTime;
        Pkt pkt;

        PifoItem(double rank, double sendPacketTime, Pkt pkt);

        bool operator<(const PifoItem& other) const;
    };

    IdealPIFOScheduler();
    static TypeId GetTypeId(void);
    bool DoEnqueue(Ptr<QueueDiscItem> item) override;
    Ptr<QueueDiscItem> DoDequeue() override;
    Ptr<const QueueDiscItem> DoPeek(void) const override;
    bool CheckConfig(void) override;
    void InitializeParams(void) override;

private:

    std::multiset<PifoItem> m_queue;
    double m_pifoSize;
    const double m_bufferSize = 5 * 1024 * 1024;

    int GetFlowLabel(Ptr<QueueDiscItem> item);
    double RankCal(Pkt pkt);
    void Drop(Ptr<QueueDiscItem> item);
};

}

#endif
