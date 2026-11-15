package com.rescene.installcheck;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.*;
import android.content.pm.*;
import android.net.Uri;
import android.os.*;
import android.provider.Settings;
import android.widget.*;
import java.io.*;
import java.security.MessageDigest;
import java.util.Arrays;

/** Local-only diagnostics. No network, analytics, account or broad storage access. */
public final class InstallCheckActivity extends Activity {
    private static final int PICK_APK = 7;
    private static final String GAME = "com.rescene.rhythm";
    private static final String CERT = "732a79726c4e08da0a2ccf7a26e56326288df5ccb53629a0eec315598371c299";
    // Replaced by the build tool from the signed public release metadata.
    private static final String EXPECTED_SHA = "@GAME_SHA256@";
    private static final long EXPECTED_BYTES = @GAME_BYTES@L;
    private static final String DOWNLOAD = "@GAME_DOWNLOAD@";
    private static java.lang.ref.WeakReference<InstallCheckActivity> active = new java.lang.ref.WeakReference<>(null);
    private TextView details;
    private Button install;
    private String report;
    private boolean busy;
    private File selected;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state); active = new java.lang.ref.WeakReference<>(this);
        ScrollView scroll = new ScrollView(this);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        int padding = (int)(20 * getResources().getDisplayMetrics().density);
        content.setPadding(padding, padding, padding, padding);
        scroll.addView(content); setContentView(scroll);
        TextView title = new TextView(this); title.setText("RESCÉNE Install Check"); title.setTextSize(25); content.addView(title);
        TextView intro = new TextView(this);
        intro.setText("Checks the game APK on this phone and shows Android’s detailed installation result. Everything stays on this device. No login or internet permission.");
        intro.setTextSize(16); content.addView(intro);
        button(content, "1. Download the official game APK", () -> startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(DOWNLOAD))));
        button(content, "2. Select the downloaded game APK", () -> {
            if (busy) return;
            Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT); pick.setType("*/*");
            pick.addCategory(Intent.CATEGORY_OPENABLE); startActivityForResult(pick, PICK_APK);
        });
        install = button(content, "3. Install verified APK and show result", this::installSelected); install.setEnabled(false);
        button(content, "Copy diagnostics", () -> {
            ((android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("RESCÉNE installation", details.getText()));
            Toast.makeText(this, "Diagnostics copied", Toast.LENGTH_SHORT).show();
        });
        details = new TextView(this); details.setTextSize(14); details.setTextIsSelectable(true); content.addView(details);
        report = "Device: " + Build.MANUFACTURER + " " + Build.MODEL + "\nAndroid: " + Build.VERSION.RELEASE + " (API " + Build.VERSION.SDK_INT + ")\nSupported ABIs: " + Arrays.toString(Build.SUPPORTED_ABIS) + "\nExpected game: @GAME_VERSION@\n\nSelect the game APK to check it.";
        showResult();
    }

    private Button button(LinearLayout parent, String text, Runnable action) {
        Button button = new Button(this); button.setText(text); parent.addView(button);
        button.setOnClickListener(view -> action.run()); return button;
    }

    @Override public void onResume() { super.onResume(); if (details != null) showResult(); }
    private void showResult() {
        details.setText(report + "\n\n" + getSharedPreferences("result", MODE_PRIVATE).getString("message", "No installation attempted."));
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != PICK_APK || result != RESULT_OK || data == null || data.getData() == null || busy) return;
        busy = true; install.setEnabled(false); selected = null;
        report = report.substring(0, report.indexOf("\n\n"));
        getSharedPreferences("result", MODE_PRIVATE).edit().remove("message").apply();
        details.setText(report + "\n\nChecking the selected file…");
        final Uri uri = data.getData();
        new Thread(() -> {
            File copy = new File(getCacheDir(), "game.apk");
            try {
                MessageDigest digest = MessageDigest.getInstance("SHA-256");
                long count = 0;
                try (InputStream input = getContentResolver().openInputStream(uri); OutputStream output = new FileOutputStream(copy)) {
                    if (input == null) throw new IOException("Cannot open selected file");
                    byte[] buffer = new byte[262144]; int read;
                    while ((read = input.read(buffer)) != -1) {
                        count += read;
                        if (count > EXPECTED_BYTES + 1048576) throw new IOException("Not the current official game APK: file is too large");
                        digest.update(buffer, 0, read); output.write(buffer, 0, read);
                    }
                }
                String hash = hex(digest.digest());
                String facts = "\n\nSelected bytes: " + count + "\nSHA-256: " + hash;
                if (count != EXPECTED_BYTES || !hash.equals(EXPECTED_SHA)) throw new IOException(facts + "\nCHECK FAILED: this is incomplete, altered, or a different release. Download the official APK again using button 1.");
                int flags = Build.VERSION.SDK_INT >= 28 ? PackageManager.GET_SIGNING_CERTIFICATES : PackageManager.GET_SIGNATURES;
                PackageInfo pkg = getPackageManager().getPackageArchiveInfo(copy.getAbsolutePath(), flags);
                if (pkg == null || !GAME.equals(pkg.packageName)) throw new IOException(facts + "\nAndroid cannot parse this as the RESCÉNE game package.");
                Signature[] signatures = Build.VERSION.SDK_INT >= 28 ? pkg.signingInfo.getApkContentsSigners() : pkg.signatures;
                if (signatures == null || signatures.length != 1 || !hex(MessageDigest.getInstance("SHA-256").digest(signatures[0].toByteArray())).equals(CERT)) throw new IOException(facts + "\nThe signing certificate does not match the official game.");
                boolean arm64 = Arrays.asList(Build.SUPPORTED_ABIS).contains("arm64-v8a");
                report = report.substring(0, report.indexOf("\n\n")) + facts + "\nPackage: " + pkg.packageName + "\nVersion: " + pkg.versionName + "\nSigning certificate: MATCH\nDownload integrity: MATCH\nARM64 support: " + (arm64 ? "YES" : "NO — current game requires ARM64");
                if (arm64) selected = copy; else copy.delete();
            } catch (Exception error) { copy.delete(); report += "\n\n" + error.getMessage(); }
            busy = false;
            runOnUiThread(() -> { install.setEnabled(selected != null); showResult(); });
        }, "apk-check").start();
    }

    private void installSelected() {
        if (selected == null || busy) return;
        if (!getPackageManager().canRequestPackageInstalls()) {
            getSharedPreferences("result", MODE_PRIVATE).edit().putString("message", "Android requires installation permission for this helper. After enabling it, return and tap Install again.").apply();
            showResult(); startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + getPackageName()))); return;
        }
        busy = true; install.setEnabled(false);
        new Thread(() -> {
            int id = -1;
            try {
                PackageInstaller installer = getPackageManager().getPackageInstaller();
                PackageInstaller.SessionParams params = new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
                params.setAppPackageName(GAME); params.setSize(selected.length());
                id = installer.createSession(params);
                try (PackageInstaller.Session session = installer.openSession(id)) {
                    try (InputStream input = new FileInputStream(selected); OutputStream output = session.openWrite("base.apk", 0, selected.length())) {
                        byte[] buffer = new byte[262144]; int read;
                        while ((read = input.read(buffer)) != -1) output.write(buffer, 0, read);
                        session.fsync(output);
                    }
                    Intent result = new Intent(this, ResultReceiver.class).setAction("com.rescene.installcheck.RESULT");
                    int flags = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 31 ? PendingIntent.FLAG_MUTABLE : 0);
                    PendingIntent pending = PendingIntent.getBroadcast(this, id, result, flags);
                    getSharedPreferences("result", MODE_PRIVATE).edit().putString("message", "Sent to Android. Confirm the system installation prompt; the detailed result will appear here.").apply();
                    session.commit(pending.getIntentSender());
                }
            } catch (Exception error) {
                if (id >= 0) try { getPackageManager().getPackageInstaller().abandonSession(id); } catch (Exception ignored) { }
                getSharedPreferences("result", MODE_PRIVATE).edit().putString("message", "Installer exception: " + error).apply();
            }
            busy = false; runOnUiThread(() -> { install.setEnabled(selected != null); showResult(); });
        }, "apk-install").start();
    }

    private static String hex(byte[] data) {
        StringBuilder value = new StringBuilder(); for (byte b : data) value.append(String.format(java.util.Locale.ROOT, "%02x", b & 255)); return value.toString();
    }

    public static final class ResultReceiver extends BroadcastReceiver {
        @Override public void onReceive(Context context, Intent intent) {
            int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE);
            if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                Intent confirm = intent.getParcelableExtra(Intent.EXTRA_INTENT);
                if (confirm != null) { confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK); InstallCheckActivity activity = active.get();
                    if (activity != null) activity.startActivity(confirm); else context.startActivity(confirm); }
                return;
            }
            String message = (status == PackageInstaller.STATUS_SUCCESS ? "INSTALLATION SUCCEEDED" : "INSTALLATION FAILED")
                + "\nStatus: " + status + "\nLegacy status: " + intent.getIntExtra("android.content.pm.extra.LEGACY_STATUS", Integer.MIN_VALUE)
                + "\nAndroid message: " + intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
            context.getSharedPreferences("result", Context.MODE_PRIVATE).edit().putString("message", message).apply();
            InstallCheckActivity activity = active.get();
            if (activity != null) activity.runOnUiThread(activity::showResult);
        }
    }
}
