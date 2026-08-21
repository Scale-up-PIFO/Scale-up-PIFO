#include <algorithm>
#include <fstream>
#include <iostream>
#include <map>
#include <unordered_map>

#include "ns3/applications-module.h"
#include "ns3/core-module.h"
#include "ns3/flow-monitor-module.h"
#include "ns3/internet-module.h"
#include "ns3/ipv4-header.h"
#include "ns3/netanim-module.h"
#include "ns3/network-module.h"
#include "ns3/point-to-point-module.h"
#include "ns3/random-variable-stream.h"
#include "ns3/stats-module.h"
#include "ns3/traffic-control-module.h"
#include "ns3/udp-header.h"
#include "ns3/packet.h"
#include "ns3/tag.h"
#include "ns3/Tenant-tag.h"
#include "ns3/Timestamptag.h"

using namespace ns3;
using namespace std;

NS_LOG_COMPONENT_DEFINE("MyTopoTCP");

const int LEAF_CNT = 9;
const int SPINE_CNT = 4;
const int SERVER_CNT = 144;
const int LINK_CNT = LEAF_CNT * SPINE_CNT + SERVER_CNT;
const int FLOW_NUM = 15000;
const char *ACCESS_RATE = "100Gbps";
const char *BACKBONE_RATE = "400Gbps";
const char *DATARATE = "10Gbps";
const char *DELAY =
    "3us";
double simulator_stop_time = 4;
const int PKTSIZE = 1448;

std::unordered_map<string, int> flow_index;
std::unordered_map<uint32_t, uint16_t> flow_port;

uint32_t websearch_count = 0;
struct FlowInfo {
  double time,regular_time;
  int tenant = 0;
  int size,flow_id;
} flow_info[FLOW_NUM];

int FlowComp(FlowInfo x, FlowInfo y) {
  if (x.tenant == y.tenant)
    return x.time < y.time;
  return x.tenant < y.tenant;
}

int FlowComp_regular(FlowInfo x, FlowInfo y) {
  if (x.tenant == y.tenant)
    return x.regular_time < y.regular_time;
  return x.tenant < y.tenant;
}

std::vector<Ipv4InterfaceContainer> interfaces(LINK_CNT);

NodeContainer leafNodes, spineNodes, serverNodes, nodes;

class MyApp : public Application
{
public:
  MyApp();
  virtual ~MyApp();

  static TypeId GetTypeId(void);
  void Setup(Ptr<Socket> socket, uint32_t sip, Ipv4Address saddr,
      Address address, uint32_t packetSize,
      uint32_t nBytes, DataRate dataRate, uint16_t dport);

private:
  virtual void StartApplication(void);
  virtual void StopApplication(void);
  void ScheduleTx(uint32_t);
  void SendPacket(void);
  Ptr<Socket> m_socket;
  Address m_peer;
  uint32_t m_packetSize;
  uint32_t m_nBytes;
  DataRate m_dataRate;
  EventId m_sendEvent;
  bool m_running;
  uint32_t m_bytesSent;

};

MyApp::MyApp()
    : m_socket(0),
      m_peer(),
      m_packetSize(0),
      m_nBytes(0),
      m_dataRate(0),
      m_sendEvent(),
      m_running(false),
      m_bytesSent(0) {}

MyApp::~MyApp() { m_socket = 0; }

TypeId MyApp::GetTypeId(void)
{
  static TypeId tid = TypeId("MyApp")
                          .SetParent<Application>()
                          .SetGroupName("Tutorial")
                          .AddConstructor<MyApp>();
  return tid;
}

void MyApp::Setup(Ptr<Socket> socket, uint32_t sip, Ipv4Address saddr,
    Address address, uint32_t packetSize,
    uint32_t nBytes, DataRate dataRate, uint16_t dport)
{
  m_socket = socket;

  if(dport == 0){
    dport = 999;
  }
  m_socket->Bind(InetSocketAddress(saddr, dport));
  flow_port[sip] = dport;

  m_peer = address;
  m_packetSize = packetSize;
  m_nBytes = nBytes;
  m_dataRate = dataRate;
}

void MyApp::StartApplication(void)
{

  m_running = true;
  m_bytesSent = 0;
  m_socket->Connect(m_peer);
  SendPacket();
}

void MyApp::StopApplication(void)
{
  m_running = false;
  if (m_sendEvent.IsRunning())
  {
    Simulator::Cancel(m_sendEvent);
  }
  if (m_socket)
  {
    m_socket->Close();
  }
}

void MyApp::SendPacket(void)
{
  uint32_t bytesLeft = m_nBytes - m_bytesSent;
  uint32_t pktSize = std::min(m_packetSize, bytesLeft);

  Ptr<Packet> packet = Create<Packet>(pktSize);
  TenantTag tag;
  tag.SetTenantId(m_nBytes);
  packet->AddPacketTag(tag);

  Timestamptag ts;
  ts.SetTimestamp(Simulator::Now());
  packet->AddPacketTag(ts);

  m_socket->Send(packet);

  m_bytesSent += pktSize;
  if (m_bytesSent < m_nBytes)
  {
    ScheduleTx(pktSize);
  }

}

void MyApp::ScheduleTx(uint32_t pktSize)
{
  if (m_running)
  {
    Time tNext(Seconds(pktSize * 8 /
                       static_cast<double>(m_dataRate.GetBitRate())));
    m_sendEvent = Simulator::Schedule(tNext, &MyApp::SendPacket, this);
  }
}

ofstream Output;

class TraceFlow
{
private:
  ifstream flow;
  uint32_t flow_num;
  struct FlowInput
  {
    uint32_t src, dst, byte_count;
    uint16_t dport;
    double start_time;
    uint32_t idx;
    uint32_t tenant;
  };

  FlowInput flow_input = {0};

public:
  enum type
  {
    WebSearch,
    Hadoop
  } flow_type;

  TraceFlow(string file_name, type flow_t)
  {
    flow.open(file_name);
    flow >> flow_num;
    if (flow_t == WebSearch)
      websearch_count = flow_num;
    flow_input.idx = 0;
    flow_type = flow_t;
  }

  void ReadFlowInput()
  {
    flow >> flow_input.src >> flow_input.dst >>
        flow_input.dport >> flow_input.byte_count >> flow_input.start_time >>flow_input.tenant;

    if (flow_input.byte_count == 0) {
        flow_input.byte_count = PKTSIZE;
    }

    if (flow_type == Hadoop) {

    }
    else {

      flow_info[flow_input.idx].tenant = flow_input.tenant;
      flow_info[flow_input.idx].size = flow_input.byte_count;
      flow_info[flow_input.idx].flow_id=flow_input.dport;
    }

  }

    void ScheduleFlowInput()
{
  Address sinkAddress;
  ApplicationContainer sinkApp;

  if (flow_type == WebSearch) {

    sinkAddress = InetSocketAddress(interfaces[flow_input.dst].GetAddress(1), 30011);
    PacketSinkHelper sinkHelper("ns3::TcpSocketFactory",
        InetSocketAddress(Ipv4Address::GetAny(), 30011));
    sinkApp = sinkHelper.Install(serverNodes.Get(flow_input.dst));
  } else {

    sinkAddress = InetSocketAddress(interfaces[flow_input.dst].GetAddress(1), 30012);
    PacketSinkHelper sinkHelper("ns3::UdpSocketFactory",
        InetSocketAddress(Ipv4Address::GetAny(), 30012));
    sinkApp = sinkHelper.Install(serverNodes.Get(flow_input.dst));
  }

  sinkApp.Start(Seconds(0));
  sinkApp.Stop(Seconds(simulator_stop_time));

  Ptr<Socket> ns3Socket;

  if (flow_type == WebSearch) {

    TypeId tid = TypeId::LookupByName("ns3::TcpNewReno");
    Config::Set("/NodeList/*/$ns3::TcpL4Protocol/SocketType", TypeIdValue(tid));
    ns3Socket = Socket::CreateSocket(serverNodes.Get(flow_input.src), TcpSocketFactory::GetTypeId());
    ns3Socket->SetAttribute("SndBufSize", UintegerValue(1438000000));
  } else {

    ns3Socket = Socket::CreateSocket(serverNodes.Get(flow_input.src), UdpSocketFactory::GetTypeId());
  }

  Ipv4Address saddr = interfaces[flow_input.src].GetAddress(1);
  uint32_t sip = saddr.Get();

  Ptr<MyApp> app = CreateObject<MyApp>();
  app->Setup(ns3Socket, sip, saddr, sinkAddress,
             PKTSIZE, flow_input.byte_count,
             DataRate(DATARATE), flow_input.dport);

  serverNodes.Get(flow_input.src)->AddApplication(app);

  if (flow_type == WebSearch) {
    stringstream ss;
    ss << sip << flow_port[sip];
    string flowlabel = ss.str();
    Output << flowlabel.c_str() << " ";
    Output << flow_input.src << " " << flow_input.dst << " ";
    Output << flow_input.byte_count << " " << flow_input.tenant << endl;

    flow_index[flowlabel] = flow_input.idx;
  }

  app->SetStartTime(Seconds(flow_input.start_time) - Simulator::Now());
}

  void Input()
  {
    if (flow_type == WebSearch) {
      string path = "ScaleUP_PIFO/log/DynamicIntervalRRPIFOScheduler_10MB_adjust500.txt";
      Output.open(path);
      Output << flow_num << endl;
    }
    while (flow_input.idx < flow_num) {
      ReadFlowInput();
      ScheduleFlowInput();
      flow_input.idx++;
    }
    flow.close();
    if (flow_type == WebSearch)
      Output.close();
  }

};

int main(int argc, char *argv[])
{

  Config::SetDefault("ns3::TcpSocket::DelAckTimeout", TimeValue(Seconds(0.0)));

  Config::SetDefault("ns3::RttEstimator::InitialEstimation",
                     TimeValue(Seconds(0.000012)));
  Config::SetDefault("ns3::TcpSocket::ConnTimeout",
                     TimeValue(Seconds(0.000060)));
  Config::SetDefault("ns3::TcpSocketBase::MinRto",
                     TimeValue(Seconds(0.000060)));
  Config::SetDefault("ns3::TcpSocketBase::ClockGranularity",
                     TimeValue(MilliSeconds(0.012)));

  Config::SetDefault("ns3::TcpSocket::DataRetries", UintegerValue(100));
  Config::SetDefault("ns3::TcpSocket::ConnCount", UintegerValue(100));
  Config::SetDefault("ns3::TcpSocket::SegmentSize", UintegerValue(1448));

  string webTrafficFile = "./traffic_gen/ScaleUP_Trace/traffic_ws_load40_dport.txt";
  string hadoopTrafficFile = "./traffic_gen/ScaleUP_Trace/traffic_udp_load40_dport.txt";

  CommandLine cmd;

  cmd.AddValue("web", "Path to the Web traffic file", webTrafficFile);
  cmd.AddValue("hadoop", "Path to the Hadoop traffic file", hadoopTrafficFile);
  cmd.Parse(argc, argv);
  Time::SetResolution(Time::NS);

  TraceFlow web_search(webTrafficFile, TraceFlow::WebSearch),
            hadoop(hadoopTrafficFile, TraceFlow::Hadoop);

  serverNodes.Create(SERVER_CNT);
  leafNodes.Create(LEAF_CNT);
  spineNodes.Create(SPINE_CNT);

  nodes = NodeContainer(leafNodes, spineNodes, serverNodes);

  PointToPointHelper backboneHelper;
  backboneHelper.SetDeviceAttribute("DataRate", StringValue(BACKBONE_RATE));
  backboneHelper.SetChannelAttribute("Delay", StringValue(DELAY));
  backboneHelper.SetQueue("ns3::DropTailQueue",
                              "MaxPackets", UintegerValue(100));
  PointToPointHelper accessHelper;
  accessHelper.SetDeviceAttribute("DataRate", StringValue(ACCESS_RATE));
  accessHelper.SetChannelAttribute("Delay", StringValue(DELAY));
  accessHelper.SetQueue("ns3::DropTailQueue",
                            "MaxPackets", UintegerValue(100));

  std::vector<NetDeviceContainer> devices(LINK_CNT);
  int device_cnt = 0;
  for (int i = 0, j; i < SERVER_CNT; ++i)
  {
    j = i / (SERVER_CNT / LEAF_CNT);
    devices[device_cnt] =
        accessHelper.Install(leafNodes.Get(j), serverNodes.Get(i));
    device_cnt++;
  }
  for (int i = 0; i < LEAF_CNT; ++i)
    for (int j = 0; j < SPINE_CNT; ++j)
    {
      devices[device_cnt] =
          backboneHelper.Install(leafNodes.Get(i), spineNodes.Get(j));
      device_cnt++;
    }

  InternetStackHelper stack;
  stack.Install(nodes);

  Ipv4AddressHelper address;
  for (uint32_t i = 0; i < LINK_CNT; i++)
  {
    std::ostringstream subset;
    subset << "10.1." << i + 1 << ".0";

    address.SetBase(subset.str().c_str(), "255.255.255.0");
    interfaces[i] = address.Assign(
        devices[i]);
  }

  TrafficControlHelper tch;
  for (int i = 0; i < LINK_CNT; i++)
  {
    tch.Uninstall(devices[i]);
  }
  tch.SetRootQueueDisc("ns3::DynamicIntervalRRPIFOScheduler");
  for (int i = 0; i < LINK_CNT; ++i)
  {
    tch.Install(devices[i]);
  }

  Ipv4GlobalRoutingHelper::PopulateRoutingTables();

  web_search.Input();
  hadoop.Input();

  FlowMonitorHelper fmhelper;
  Ptr<FlowMonitor> monitor = fmhelper.Install(nodes);

  Simulator::Stop(Seconds(simulator_stop_time));
  Simulator::Run();

  Ptr<Ipv4FlowClassifier> classifier =
    DynamicCast<Ipv4FlowClassifier> (fmhelper.GetClassifier ());
FlowMonitor::FlowStatsContainer stats = monitor->GetFlowStats ();

std::vector<FlowInfo> completed_websearch_flows_info;

for (std::map<FlowId, FlowMonitor::FlowStats>::const_iterator i = stats.begin (); i != stats.end (); ++i) {
    Ipv4FlowClassifier::FiveTuple t = classifier->FindFlow (i->first);
    stringstream ss;
    ss << t.sourceAddress.Get() << t.sourcePort;
    string flowlabel = ss.str();

    if (flow_index.count(flowlabel) == 0)
        continue;

    if (i->second.rxPackets == 0) {
        continue;
    }

    int idx = flow_index[flowlabel];
    double start_time = i->second.timeFirstRxPacket.GetSeconds();
    double end_time = i->second.timeLastRxPacket.GetSeconds();

    FlowInfo current_flow_info = flow_info[idx];
    current_flow_info.time = end_time - start_time;
    current_flow_info.regular_time = current_flow_info.time / current_flow_info.size;

    completed_websearch_flows_info.push_back(current_flow_info);
}

uint32_t completed_count = completed_websearch_flows_info.size();

sort(completed_websearch_flows_info.begin(), completed_websearch_flows_info.end(), FlowComp_regular);

ofstream ss_fct("ScaleUP_PIFO/Results/AllDynamicIntervalRRPIFOScheduler_10MB_adjust500.txt", std::ios::out );
for (const auto& info : completed_websearch_flows_info) {
    ss_fct << info.time << " " << info.size << " " <<
            info.size * 8 / (1024 * 1024 * info.time) <<
            " " << info.tenant << endl;
}

ofstream ss_95("ScaleUP_PIFO/Results/95DynamicIntervalRRPIFOScheduler_10MB_adjust500.txt", std::ios::out );

double totalRegularTime = 0;
for (const auto& info : completed_websearch_flows_info) {
    totalRegularTime += info.regular_time;
}
double p95RegularTime = 0.0;
double avgRegularTime = 0.0;
double maxRegularTime = 0.0;

if (completed_count > 0) {
    p95RegularTime = completed_websearch_flows_info[static_cast<uint32_t>(0.95 * completed_count)].regular_time;
    avgRegularTime = totalRegularTime / completed_count;
    maxRegularTime = completed_websearch_flows_info[completed_count - 1].regular_time;
}

ss_95 << "Normalized FCT P95: " << p95RegularTime << endl;
ss_95 << "Normalized FCT Avg: " << avgRegularTime << endl;
ss_95 << "Normalized FCT Max: " << maxRegularTime << endl;
ss_95 << endl;

sort(completed_websearch_flows_info.begin(), completed_websearch_flows_info.end(), FlowComp);

double totalTime = 0;
for (const auto& info : completed_websearch_flows_info) {
    totalTime += info.time;
}
double p95Time = 0.0;
double avgTime = 0.0;
double maxTime = 0.0;

if (completed_count > 0) {
    p95Time = completed_websearch_flows_info[static_cast<uint32_t>(0.95 * completed_count)].time;
    avgTime = totalTime / completed_count;
    maxTime = completed_websearch_flows_info[completed_count - 1].time;
}

ss_95 << "Absolute FCT P95: " << p95Time << endl;
ss_95 << "Absolute FCT Avg: " << avgTime << endl;
ss_95 << "Absolute FCT Max: " << maxTime << endl;

  Simulator::Destroy();

  return 0;
}

