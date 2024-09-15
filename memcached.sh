THREADS=24
RUNNER_IP="192.168.2.132"
KEY="/root/.ssh/sky5"
USER="ryan"

MEMCACHE_PID=""
MSNPROOT="/memsnap"
DISK="/dev/nvd0"
#MSNPFILE="$MSNPROOT/dummyfile"
MSNPFILE="dummyfile"

MEMCACHED_DIR="/root/memsnap-artifact/memcached"
MEMCACHED_IP="192.168.2.131"
MEMCACHED_ARGS="-R 10000 -m 16384 -u root -o no_lru_crawler,no_lru_maintainer -C -c 4096"
MEMCACHED_OBJSNAP_ARGS="-e $MSNPFILE"

MEMTIER_ARGS="-d 512 -n 2500 -t 12 -c 64 -s $MEMCACHED_IP -p 11211 -4 -P memcache_text"

mc_init()
{
	kldload objsnap.ko
	objinit $DISK

	#kldload memsnap.ko
	#mkdir -p "$MSNPROOT"
	#mount -t msnp msnp "$MSNPROOT"

	$MEMCACHED_DIR/memcached $1 $MEMCACHED_ARGS "-t $THREADS" > /tmp/serverout 2> /tmp/serverout  &
}

mc_fini()
{
	kill -INT $MEMCACHE_PID 2> /dev/null > /dev/null
	sleep 2

	#umount "$MSNPROOT"
	#sleep 2

	#kldunload memsnap
	kldunload objsnap
}

runner_go() {
	READ="$2"
	WRITE="$3"
	ssh -i "$KEY" $USER@$RUNNER_IP "memtier_benchmark --ratio=$WRITE:$READ $MEMTIER_ARGS" 2> /dev/null > /tmp/results
	ops=$(cat /tmp/results | grep -A 7 "ALL STATS" | tail -n 4 | awk '{print $2}' | tail -n 1)
	set_lat=$(cat /tmp/results | grep -A 7 "ALL STATS" | tail -n 4 | awk '{print $5}' | tail -n 1)
	echo "$1 $2 $3 $ops $set_lat"
}

build() {
	cur=$PWD
	cd $MEMCACHED_DIR
	make clean 2> /dev/null > /dev/null
	./autogen.sh
	./configure
	make CFLAGS="$1" -j 8  2> /dev/null > /dev/null
	cd $cur
}


run_objsnap() {
	build "-DOBJSNAP=1"
	for i in "1 9" "2 8" "4 6" "1 1" "6 4" "8 2" "9 1"
	do
		for t in $(seq 1 10)
		do
			set -- $i
			mc_init "$MEMCACHED_OBJSNAP_ARGS"
			sleep 5

			results=$(runner_go "objsnap" $2 $1)
			sleep 5
			mc_fini
			set -- $results
			if [ "$5" != "-nan" ]; then
				sleep 5
				break
			fi
		done
		echo "$1,$2,$3,$4,$5"
	done
}

run_base() {
	build ""
	for i in "1 9" "2 8" "4 6" "1 1" "6 4" "8 2" "9 1"
	do
		for t in $(seq 1 10)
		do
			set -- $i
			mc_init ""
			sleep 5
			results=$(runner_go "base" $2 $1)
			sleep 5
			mc_fini
			set -- $results
			if [ "$5" != "-nan" ]; then
				sleep 5
				break
			fi
		done
		echo "$1,$2,$3,$4,$5"
	done
}

run_objsnap_thread() {
	build "-DOBJSNAP=1"
	for i in $(seq 1 10 24)
	do
		for t in $(seq 1 10)
		do
			export THREADS=$i
			mc_init "$MEMCACHED_OBJSNAP_ARGS"
			sleep 5
			results=$(runner_go "objsnap" 5 5)
			sleep 5
			mc_fini
			set -- $results
			if [ "$5" != "-nan" ]; then
				sleep 5
				break
			fi
		done
		echo "$1,$i,$2,$3,$4,$5"
	done

}

run_base_thread() {
	build ""
	for i in $(seq 1 10 24)
	do
		for t in $(seq 1 10)
		do
			export THREADS=$i
			mc_init ""
			sleep 5
			results=$(runner_go "base" 5 5)
			sleep 5
			mc_fini
			set -- $results
			if [ "$5" != "-nan" ]; then
				sleep 5
				break
			fi
		done
		echo "$1,$i,$2,$3,$4,$5"
	done

}

mc_fini
#echo "type,read,write,ops,set_lat_ms" > memcached
#run_objsnap >> memcached
#run_base >> memcached
echo "type,thread_count,read,write,ops,set_lat_ms" > memcached_thread
run_objsnap_thread >> memcached_thread
run_base_thread >> memcached_thread


