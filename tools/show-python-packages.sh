#! /bin/bash

for j in $(find / -name site-packages 2>/dev/null)
do
    echo "--> contents of site-packages dir ------------------------------"
    echo $j
    #find $j | egrep -q '(scapy|ptf|nnpy)'
    find $j
done
for j in $(find / -name dist-packages 2>/dev/null)
do
    echo "--> contents of dist-packages dir ------------------------------"
    echo $j
    #find $j | egrep -q '(scapy|ptf|nnpy)'
    find $j
done
