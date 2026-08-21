#include "PacksScheduler.h"

namespace ns3 {

NS_OBJECT_ENSURE_REGISTERED(PacksScheduler);

PacksScheduler::Pkt::Pkt(Ptr<QueueDiscItem> pktid, int flowid, int length, int flow_size)
    : pktid(pktid), flowid(flowid), length(length), flow_size(flow_size) {}

PacksScheduler::Element::Element(double rank, Pkt pkt)
    : rank(rank), pkt(pkt) {}

TypeId PacksScheduler::GetTypeId(void) {
    static TypeId tid = TypeId("ns3::PacksScheduler")
        .SetParent<QueueDisc>()
        .SetGroupName("TrafficControl")
        .AddConstructor<PacksScheduler>()
        .AddAttribute("FifoNum", "Number of FIFO queues.",
                      UintegerValue(4), MakeUintegerAccessor(&PacksScheduler::m_fifoNum),
                      MakeUintegerChecker<int>())
        .AddAttribute("BufferSize", "Total buffer size.",
                      DoubleValue(10 * 1024 * 1024), MakeDoubleAccessor(&PacksScheduler::m_bufferSize),
                      MakeDoubleChecker<double>())
        .AddAttribute("WindowSize", "Sliding window size.",
                      UintegerValue(20), MakeUintegerAccessor(&PacksScheduler::m_windowSize),
                      MakeUintegerChecker<int>())
        .AddAttribute("K", "Admission control parameter.",
                      DoubleValue(0.1), MakeDoubleAccessor(&PacksScheduler::m_k),
                      MakeDoubleChecker<double>());
    return tid;
}

PacksScheduler::PacksScheduler() {

    m_fifoNum = 4;
    m_windowSize = 20;
    m_k = 0.1;

    InitializeParams();
}
void PacksScheduler::InitializeParams(void) {
    m_bufferPerQueue = m_bufferSize / m_fifoNum;
    m_slidingWindow.assign(m_windowSize, 0.0);
    m_windowPointer = 0;
    m_fifos.assign(m_fifoNum, std::deque<Element>());
    m_fifoSizes.assign(m_fifoNum, 0.0);
}

int PacksScheduler::GetFlowLabel(Ptr<QueueDiscItem> item) {
        Ptr<const Ipv4QueueDiscItem> ipItem = DynamicCast<const Ipv4QueueDiscItem>(item);
    if (!ipItem) {
        return -1;
    }

    Ptr<const Packet> packet = ipItem->GetPacket();
    Ipv4Header ipv4Header;

    packet->PeekHeader(ipv4Header);

    uint8_t protocol = ipv4Header.GetProtocol();
    uint16_t sourcePort = 0;
    uint16_t destPort = 0;

    if (protocol == 6) {
        TcpHeader tcpHeader;

        packet->PeekHeader(tcpHeader);
        sourcePort = tcpHeader.GetSourcePort();
        destPort = tcpHeader.GetDestinationPort();
    } else if (protocol == 17) {
        UdpHeader udpHeader;

        packet->PeekHeader(udpHeader);
        sourcePort = udpHeader.GetSourcePort();
        destPort = udpHeader.GetDestinationPort();
    } else {

        return -1;
    }

    int flowId = 65535;
    if (sourcePort < 30000) {
        flowId = sourcePort;
    } else if (destPort < 30000) {
        flowId = destPort;
    }

    if (flowId == 65535) {
        flowId = 1001;
    }

    return flowId;
}

double PacksScheduler::RankCal(Pkt pkt) {

    return pkt.flow_size;
}

void PacksScheduler::Drop(Ptr<QueueDiscItem> item) {
    QueueDisc::Drop(item);
}

bool PacksScheduler::DoEnqueue(Ptr<QueueDiscItem> item) {
    Ptr<Packet> packet = GetPointer(item->GetPacket());
    TenantTag my_tag;
    packet->PeekPacketTag(my_tag);
    int flow_size = my_tag.GetTenantId();
    if (flow_size == 100000001) {
        flow_size = 1;
    }
    int packet_size = packet->GetSize();
    int flow_id = GetFlowLabel(item);

    Pkt pkt(item, flow_id, packet_size, flow_size);
    double rank = RankCal(pkt);
    Element element(rank, pkt);

    m_slidingWindow[m_windowPointer % m_windowSize] = rank;
    m_windowPointer++;

    int smallerCount = 0;
    for (double r : m_slidingWindow) {
        if (r < rank) {
            smallerCount++;
        }
    }
    double quantile = static_cast<double>(smallerCount) / m_windowSize;
    double B = m_bufferSize;

    for (int i = 0; i < m_fifoNum; ++i) {
        double remainingSum = 0;
        for (int j = 0; j <= i; ++j) {
            double used = m_fifoSizes[j];
            double remaining = m_bufferPerQueue - used;
            remainingSum += remaining;
        }
        if (remainingSum < 0) {
            remainingSum = 0;
        }

        double threshold = remainingSum / (B * (1 - m_k));

        if (quantile <= threshold) {
            if (m_fifoSizes[i] + pkt.length <= m_bufferPerQueue) {
                m_fifos[i].push_back(element);
                m_fifoSizes[i] += pkt.length;
                return true;
            }
        }
    }

    Drop(item);
    return false;
}

Ptr<QueueDiscItem> PacksScheduler::DoDequeue() {
    for (int i = 0; i < m_fifoNum; ++i) {
        if (!m_fifos[i].empty()) {
            Element element = m_fifos[i].front();
            m_fifos[i].pop_front();
            m_fifoSizes[i] -= element.pkt.length;
            return element.pkt.pktid;
        }
    }
    return nullptr;
}

Ptr<const QueueDiscItem> PacksScheduler::DoPeek(void) const {
    for (int i = 0; i < m_fifoNum; ++i) {
        if (!m_fifos[i].empty()) {
            return m_fifos[i].front().pkt.pktid;
        }
    }
    return nullptr;
}

bool PacksScheduler::CheckConfig(void) {
    return true;
}

}
