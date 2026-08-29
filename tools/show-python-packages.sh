#! /bin/bash

for j in $(find / -name site-packages 2>/dev/null)
do
    echo "----------------------------------------------------------------------"
    echo $j
    find $j | egrep '(scapy|ptf|nnpy)'
done
for j in $(find / -name dist-packages 2>/dev/null)
do
    echo "----------------------------------------------------------------------"
    echo $j
    find $j | egrep '(scapy|ptf|nnpy)'
done
