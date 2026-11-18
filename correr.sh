#!/bin/bash
# uso: sudo ./correr.sh c01 4:20 8:20 14:20 5:20   (tasaMbit:segundos por fase)
IFACE=eno1
SERVER=192.168.50.20
RUN=$1; shift
 
# 1) muestreo de la cola
( while true; do date +%s.%N; tc -j -s qdisc show dev "$IFACE"; sleep 1; done ) > ${RUN}_cola.log &
CPID=$!
 
# 2) captura continua
tcpdump -i "$IFACE" -nn -s 96 -B 4096 -w ${RUN}.pcap \
  "src host 192.168.50.10 and dst host $SERVER and udp dst port 5201" 2> ${RUN}_tcpdump.txt &
TPID=$!
sleep 5
 
# 3) fases de tráfico (se registra la hora de cada una)
: > ${RUN}_fases.log
i=1
for f in "$@"; do
  rate=${f%%:*}; dur=${f##*:}
  echo "$(date +%s.%N) fase$i ${rate}Mbit/s ${dur}s" >> ${RUN}_fases.log
  iperf3 -c $SERVER -u -b ${rate}M -l 1200 -t $dur -i 1 --get-server-output -J \
    > ${RUN}_fase$(printf %02d $i).json
  i=$((i+1))
done
sleep 5
 
# 4) detener y exportar
kill -INT $TPID; wait $TPID 2>/dev/null
kill $CPID
tshark -r ${RUN}.pcap -T fields -E header=y -E separator=, \
  -e frame.time_epoch -e frame.len > ${RUN}_paquetes.csv
 
echo "== descartes de la cola =="; tc -s qdisc show dev "$IFACE" | grep dropped
echo "== paquetes capturados =="; wc -l ${RUN}_paquetes.csv
cat ${RUN}_tcpdump.txt
chown $SUDO_USER: ${RUN}_* 2>/dev/null
