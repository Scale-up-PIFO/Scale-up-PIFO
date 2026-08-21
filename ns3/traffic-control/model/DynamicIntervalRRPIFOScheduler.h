#ifndef DYNAMIC_INTERVAL_RR_PIFO_SCHEDULER_H
#define DYNAMIC_INTERVAL_RR_PIFO_SCHEDULER_H

#include <iostream>
#include <vector>
#include <queue>
#include <deque>
#include <set>
#include <numeric>
#include <algorithm>
#include <limits>
#include "ns3/ipv4-queue-disc-item.h"
#include "ns3/ptr.h"
#include "ns3/tcp-header.h"
#include "ns3/Tenant-tag.h"
#include "ns3/queue-disc.h"
#include "ns3/udp-header.h"
#include "ns3/Timestamptag.h"
#include <ns3/nstime.h>

namespace ns3 {

class DynamicIntervalRRPIFOScheduler : public QueueDisc {
public:

    struct Pkt {
        Ptr<QueueDiscItem> pktid;
        int flowid;
        int length;
        int flow_size;
        Pkt(Ptr<QueueDiscItem> pktid, int flowid, int length, int flow_size);
    };

    struct PifoItem {
        double rank;
        double sendPacketTime;
        Pkt pkt;
        PifoItem(double rank, double sendPacketTime, Pkt pkt);
        bool operator<(const PifoItem& other) const;
    };

    DynamicIntervalRRPIFOScheduler();
    static TypeId GetTypeId(void);
    void InitializeParams(void) override;
    void TryDequeue(void);
    bool DoEnqueue(Ptr<QueueDiscItem> item) override;
    Ptr<QueueDiscItem> DoDequeue() override;
    Ptr<const QueueDiscItem> DoPeek(void) const override;
    bool CheckConfig(void) override;

private:

    const int NUM_LOAD_BALANCERS = 2;
    const int NUM_PIFOS = 4;
    int m_numIntervals=16;
    const int INTERVAL_TOTAL_LENGTH = 100000;
    double m_intervalLength;
    const int REFILL_BATCH_SIZE = 8;
    const int ADJUST_PERIOD = 1000;
    const double PIFO_BUFFER_SIZE_PER_PIFO = 10 * 1024 * 1024 / NUM_PIFOS;
    DataRate m_linkBandwidth;

    double m_fifoBufferSize;
    std::vector<double> m_fifoBufferUsage;
    double m_perFifoBufferLimit;
    std::vector<double> m_pifoCurrentSizes;
    std::vector<double> m_sharedIntervalBorders;
    int m_loadBalancerIndex;
    int m_dequeueLbIndex;
    int m_pifoIndex;
    int m_adjustCounter;
    int m_ackInputPointer;
    int m_ackOutputPointer;

    std::vector<std::multiset<PifoItem>> m_pifos;
    std::vector<std::deque<PifoItem>> m_fifos;
    std::vector<double> m_borderCounts;
    std::vector<std::vector<std::vector<int>>> m_intervalCounters;
    std::deque<Ptr<QueueDiscItem>> m_ackFifo;

    std::vector<std::vector<std::vector<int>>> InitIntervalCountersWithPattern();
    int GetIntervalIndex(double rank);
    int SelectBestPifo(int lb_id, int interval_index);
    void RefillFromFifo(int pifo_id);
    std::vector<int> CalculateCurrentCounts();
    void AdjustIntervals();
    int GetFlowLabel(Ptr<QueueDiscItem> item);
    double RankCal(Pkt pkt);
    void Drop(Ptr<QueueDiscItem> item);
};

}

#endif
