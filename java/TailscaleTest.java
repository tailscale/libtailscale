package com.tailscale;

import com.tailscale.Tailscale;
import java.io.OutputStream;
import java.io.InputStream;
import java.io.PrintWriter;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.IOException;
import java.net.ServerSocket;
import java.net.Authenticator;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.Socket;
import java.net.PasswordAuthentication;
import java.net.ProxySelector;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Duration;

public class TailscaleTest {
	static {
		Path relwd = Paths.get("");
		String cwd = relwd.toAbsolutePath().toString();
		System.load(cwd + "/" + System.mapLibraryName("testcontrol"));
		System.load(cwd + "/" + System.mapLibraryName("testcontroljni"));
	}

	static native String run();

	public static void main(String[] args) throws Exception {
		String controlURL = run();

		Tailscale.Handle sd1 = new Tailscale.Handle();
		sd1.disableLog();
		sd1.setDir(Files.createTempDirectory("tailscale-sd1").toFile().getAbsolutePath());
		sd1.setEphemeral(true);
		sd1.setControlURL(controlURL);
		sd1.up();

		Tailscale.LocalAPI api = sd1.localAPI();
		api.status();

		Tailscale.Handle sd2 = new Tailscale.Handle();
		sd2.disableLog();
		sd1.setDir(Files.createTempDirectory("tailscale-sd2").toFile().getAbsolutePath());
		sd2.setEphemeral(true);
		sd2.setControlURL(controlURL);
		sd2.up();

		Tailscale.HandleListener ln = sd1.listen("tcp", ":18081");
		Tailscale.HandleConn c1 = sd2.dial("tcp", "100.64.0.1:18081");
		Tailscale.HandleConn c2 = ln.accept();

		String want = "Hello from Java";

		OutputStream out = c1.getOutputStream();
		new PrintWriter(out).printf("%s\n", want).close();
		InputStream in = c2.getInputStream();
		String got = new BufferedReader(new InputStreamReader(in)).readLine();

		if (!got.equals(want)) {
			System.out.printf("bad stream, got: '%s', want '%s'\n", got, want);
			System.exit(1);
		}

		out.close();
		in.close();
		//c1.close();
		//c2.close();

		ln.close();
		sd1.close();
		sd2.close();
	}
}
