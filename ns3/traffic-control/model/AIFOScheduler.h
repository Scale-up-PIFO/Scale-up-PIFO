#ifndef AIFO_SCHEDULER_H
#define AIFO_SCHEDULER_H

#include <vector>
#include <deque>
#include <numeric>
#include <algorithm>
#include <iostream>
#include "ns3/queue-disc.h"
#include "ns3/ipv4-queue-disc-item.h"
#include "ns3/ptr.h"
#include "ns3/tcp-header.h"
#include "ns3/Tenant-tag.h"
#include "ns3/udp-header.h"
namespace ns3 {

class AIFOScheduler : public QueueDisc {
public:

    struct Pkt {
        Ptr<QueueDiscItem> pktid;
        int flowid;
        int length;
        int flow_size;
        Pkt(Ptr<QueueDiscItem> pktid, int flowid, int length, int flow_size);
    };

    struct Element {
        double rank;
        Pkt pkt;
        Element(double rank, Pkt pkt);
    };

    AIFOScheduler();
    static TypeId GetTypeId(void);
    void InitializeParams(void) override;
    bool DoEnqueue(Ptr<QueueDiscItem> item) override;
    Ptr<QueueDiscItem> DoDequeue() override;
    Ptr<const QueueDiscItem> DoPeek(void) const override;
    bool CheckConfig(void) override;

private:

    int m_windowSize;
    double m_bufferSize;
    double m_k;
    std::vector<double> m_slidingWindow;
    int m_windowPointer;
    std::deque<Element> m_fifoQueue;
    double m_currentBufferUsage;

    int GetFlowLabel(Ptr<QueueDiscItem> item);
    double RankCal(Pkt pkt);
    void Drop(Ptr<QueueDiscItem> item);
};

}

#endif
