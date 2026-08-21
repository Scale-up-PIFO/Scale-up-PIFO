#ifndef SP_PIFO_SCHEDULER_H
#define SP_PIFO_SCHEDULER_H

#include "ns3/queue-disc.h"
#include "ns3/ipv4-queue-disc-item.h"
#include "ns3/ptr.h"
#include "ns3/tcp-header.h"
#include "ns3/Tenant-tag.h"
#include <vector>
#include <deque>
#include <list>
#include "ns3/udp-header.h"
namespace ns3 {

class SPPIFOScheduler : public QueueDisc {
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
        Pkt pkt;
        PifoItem(double rank, Pkt pkt);
    };

    SPPIFOScheduler();
    static TypeId GetTypeId(void);
    void InitializeParams(void) override;
    bool DoEnqueue(Ptr<QueueDiscItem> item) override;
    Ptr<QueueDiscItem> DoDequeue() override;
    Ptr<const QueueDiscItem> DoPeek(void) const override;
    bool CheckConfig(void) override;

private:

    int m_fifoNum;
    double m_bufferSize;
    double m_perFifoBuffer;

    std::vector<double> m_borders;
    std::vector<double> m_fifoSizes;
    std::vector<std::deque<PifoItem>> m_fifos;

    int GetFlowLabel(Ptr<QueueDiscItem> item);
    double RankCal(Pkt pkt);
    void Drop(Ptr<QueueDiscItem> item);
};

}

#endif
