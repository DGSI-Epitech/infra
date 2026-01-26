const { execSync } = require("child_process");
const os = require("os");

function commandExists(cmd) {
    try {
        execSync(`${cmd} --version`, { stdio: "ignore" });
        return true;
    } catch {
        return false;
    }
}

function run(cmd) {
    console.log(`\n> ${cmd}`);
    execSync(cmd, { stdio: "inherit" });
}

if (commandExists("terraform")) {
    console.log("✅ Terraform already installed");
    run("terraform version");
    process.exit(0);
}

console.log("⬇️ Terraform not found, installing…");

const platform = os.platform();

try {
    if (platform === "win32") {
        if (commandExists("choco")) {
            run("choco install terraform -y");
        } else if (commandExists("winget")) {
            run("winget install HashiCorp.Terraform");
        } else {
            throw new Error("Neither choco nor winget found");
        }
    }

    else if (platform === "darwin") {
        if (!commandExists("brew")) {
            throw new Error("Homebrew not installed");
        }
        run("brew tap hashicorp/tap");
        run("brew install hashicorp/tap/terraform");
    }

    else if (platform === "linux") {
        run("sudo apt update");
        run("sudo apt install -y curl gnupg lsb-release");
        run(
            "curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg"
        );
        run(
            'echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list'
        );
        run("sudo apt update");
        run("sudo apt install -y terraform");
    }

    else {
        throw new Error(`Unsupported platform: ${platform}`);
    }

    console.log("\n✅ Terraform installed successfully");
    run("terraform version");

} catch (err) {
    console.error("\n❌ Terraform installation failed:");
    console.error(err.message);
    process.exit(1);
}
