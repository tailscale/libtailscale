# brew tap messense/macos-cross-toolchains
# brew install x86_64-unknown-linux-musl
# brew install aarch64-unknown-linux-musl

all:
	(cd .. && go build -buildmode=c-shared && mv libtailscale java/libtailscale.dylib)
	cc -I$(JAVA_HOME)/include -I$(JAVA_HOME)/include/darwin -o libtailscalejni.dylib -shared tailscalejni.c libtailscale.dylib
	$(JAVA_HOME)/bin/javac Tailscale.java NativeUtils.java
	mkdir -p com/tailscale
	mv *.class com/tailscale/

.PHONY: libtestcontrol.dylib
libtestcontrol.dylib:
	(cd ../libtestcontrol && go build -buildmode=c-shared && mv libtestcontrol ../java/libtestcontrol.dylib)
	cc -I$(JAVA_HOME)/include -I$(JAVA_HOME)/include/darwin -o libtestcontroljni.dylib -shared tailscalejni_test.c libtestcontrol.dylib

test: all libtestcontrol.dylib
	(cd ../libtestcontrol && go build -buildmode=c-shared && mv libtestcontrol ../java/libtestcontrol.dylib)
	cc -I$(JAVA_HOME)/include -I$(JAVA_HOME)/include/darwin -o libtestcontroljni.dylib -shared tailscalejni_test.c libtestcontrol.dylib
	$(JAVA_HOME)/bin/javac TailscaleTest.java
	mv *.class com/tailscale/
	$(JAVA_HOME)/bin/java -cp . com.tailscale.TailscaleTest

testjar: libtestcontrol.dylib
	./build.sh
	$(JAVA_HOME)/bin/javac -cp tailscale.jar TailscaleTest.java
	mkdir -p com/tailscale
	mv *.class com/tailscale/
	$(JAVA_HOME)/bin/java -cp .:tailscale.jar com.tailscale.TailscaleTest
