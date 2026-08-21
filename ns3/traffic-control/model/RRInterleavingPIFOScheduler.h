#ifndef RR_INTERLEAVING_PIFO_SCHEDULER_H
#define RR_INTERLEAVING_PIFO_SCHEDULER_H

#include <iostream>
#include <vector>
#include <queue>
#include <unordered_map>
#include <memory>
#include "ns3/ipv4-queue-disc-item.h"
#include "ns3/ptr.h"
#include "ns3/tcp-header.h"
#include "ns3/Tenant-tag.h"
#include "ns3/queue-disc.h"
#include <numeric>
#include <set>
#include "ns3/udp-header.h"
#include "ns3/Timestamptag.h"
namespace ns3 {

class RRInterleavingPIFOScheduler : public QueueDisc {
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

    RRInterleavingPIFOScheduler();
    static TypeId GetTypeId(void);
    void InitializeParams(void) override;
    bool DoEnqueue(Ptr<QueueDiscItem> item) override;
    Ptr<QueueDiscItem> DoDequeue() override;
    Ptr<const QueueDiscItem> DoPeek(void) const override;
    bool CheckConfig(void) override;

private:

    const int PIFO_NUM = 4;
    const double BUFFER_SIZE = 5 * 1024 * 1024;
    double m_bufferPerPifo;
    int m_inputPointer;
    int m_outputPointer;
    int m_ackInputPointer;
    int m_ackOutputPointer;

    std::vector<std::multiset<PifoItem>> m_queues;
    std::vector<double> m_pifoSizes;
    std::deque<Ptr<QueueDiscItem>> m_ackFifo;

    int GetFlowLabel(Ptr<QueueDiscItem> item);
    double RankCal(Pkt pkt);
    void Drop(Ptr<QueueDiscItem> item);
};

}

#endif
