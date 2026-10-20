# SAMM one-link install on a MikroTik router (RouterOS 7.23+, arm64 or x86_64 / CHR).
#
# Paste this ONE line into the router's terminal (WinBox > New Terminal, or SSH):
#
#   /tool fetch url="https://github.com/mhdhaidarah/samm-docker/releases/latest/download/install-routeros.rsc" dst-path=samm-install.rsc; /import samm-install.rsc
#
# Paste the same line again whenever it asks you to (after the reboot, after the power cycle, after the
# disk is ready): every step checks what is already done and carries on from there. Nothing that is already
# running is touched, and no disk is ever formatted without you typing the command yourself.
#
# What it does: checks RouterOS / CPU / memory, installs the container package, switches on container mode
# (one hard power cycle), finds an ext4 disk of at least 30 GB, points the container download folders at it,
# downloads SAMM's compose file, puts a strong random database password and bridge token in it, adds and starts
# the "samm" app, and waits until the panel answers.
#
# Lab override: `:global SAMMMINGB 5` before /import lowers the disk minimum (GB). `:global SAMMCOMPOSE "<url>"`
# uses another compose file.

:local say do={ :put ("SAMM | " . $1) }
:global SAMMMINGB
:global SAMMCOMPOSE

$say "One-link install for MikroTik. Checking this router..."

# ---- 1. RouterOS version, CPU, memory -------------------------------------------------------------------------
:local ver [/system resource get version]
:local v $ver
:if ([:typeof [:find $v " "]] != "nil") do={ :set v [:pick $v 0 [:find $v " "]] }
:local d1 [:find $v "."]
:local maj [:tonum [:pick $v 0 $d1]]
:local rest [:pick $v ($d1 + 1) [:len $v]]
:local mnr
:if ([:typeof [:find $rest "."]] = "nil") do={ :set mnr [:tonum $rest] } else={ :set mnr [:tonum [:pick $rest 0 [:find $rest "."]]] }
:if ([:typeof $maj] != "num" or [:typeof $mnr] != "num" or $maj < 7 or ($maj = 7 and $mnr < 23)) do={
    $say ("RouterOS " . $ver . " is too old. SAMM needs 7.23 or newer: System > Packages > Check For Updates, install, then paste the link again.")
    :error "SAMM: RouterOS too old"
}
:local arch [/system resource get architecture-name]
:local suffix ""
:if ($arch = "arm64") do={ :set suffix "-arm64" } else={
    :if ($arch != "x86_64") do={
        $say ("This router's CPU (" . $arch . ") cannot run SAMM. It needs an arm64 router (RB5009, hAP ax2/ax3, CCR2004/2116/2216, L009...) or x86 / CHR.")
        :error "SAMM: unsupported CPU"
    }
}
:local mem [/system resource get total-memory]
:if ($mem < 1000000000) do={
    $say ("This router has " . ($mem / 1048576) . " MB of memory; SAMM needs at least 1 GB (2 GB or more recommended).")
    :error "SAMM: not enough memory"
}
$say ("RouterOS " . $v . ", " . $arch . ", " . ($mem / 1048576) . " MB memory: OK")

# ---- 2. Container package ---------------------------------------------------------------------------------------
:if ([:len [/system package find where name="container"]] = 0) do={
    :local npk ("container-" . $v . $suffix . ".npk")
    $say ("Downloading the container package for RouterOS " . $v . "...")
    :do {
        /tool fetch url=("https://download.mikrotik.com/routeros/" . $v . "/" . $npk) dst-path=$npk
    } on-error={
        $say "Could not download it from download.mikrotik.com. Check the router's Internet and DNS, then paste the link again."
        :error "SAMM: package download failed"
    }
    $say "Downloaded. The router now REBOOTS to install it. When it is back, paste the same link again."
    :delay 3s
    /system reboot
    :error "SAMM: rebooting to install the container package"
}
:if ([/system package get [find where name="container"] disabled]) do={
    /system package enable container
    $say "The container package was switched off; it is on now. The router REBOOTS. Then paste the link again."
    :delay 3s
    /system reboot
    :error "SAMM: rebooting to enable the container package"
}
$say "Container package: OK"

# ---- 3. Container mode (one hard power cycle) --------------------------------------------------------------------
:if (![/system device-mode get container]) do={
    $say "Container mode must be switched on once, and the router has to CONFIRM it:"
    $say "  >>> within 5 minutes, UNPLUG THE ROUTER'S POWER (or press its reset/mode button). <<<"
    $say "  A normal reboot does NOT count. On a CHR: power the VM off from the hypervisor, then start it."
    $say "When it is back, paste the same link again."
    /system device-mode update container=yes
    :error "SAMM: waiting for the power cycle"
}
$say "Container mode: OK"

# ---- 4. Disk ----------------------------------------------------------------------------------------------------
:local mingb 30
:if ([:typeof $SAMMMINGB] = "num") do={ :set mingb $SAMMMINGB }
:local minbytes ($mingb * 1000000000)
:local mp ""
:local best 0
:foreach d in=[/disk find where fs="ext4"] do={
    :local sz [/disk get $d size]
    :local m [/disk get $d mount-point]
    :if ([:typeof $sz] = "num" and $sz >= $minbytes and [:len $m] > 0 and $sz > $best) do={ :set best $sz; :set mp $m }
}
:if ([:len $mp] = 0) do={
    :local cand ""
    :foreach d in=[/disk find where type="hardware"] do={
        :local sz [/disk get $d size]
        :if ([:typeof $sz] = "num" and $sz >= $minbytes and [:len $cand] = 0) do={ :set cand [/disk get $d slot] }
    }
    :if ([:len $cand] = 0) do={
        $say ("No disk for SAMM. Plug in a USB flash / SSD / NVMe of at least " . $mingb . " GB (SAMM's database and images live there, never on the router's own storage), then paste the link again.")
        :error "SAMM: no disk"
    }
    $say ("Disk " . $cand . " is big enough but is not formatted ext4. Formatting ERASES everything on it. If that is fine, run:")
    $say ("    /disk format " . $cand . " file-system=ext4")
    $say "then paste the link again."
    :error "SAMM: disk needs formatting"
}
$say ("Disk: " . $mp . " (" . ($best / 1000000000) . " GB, ext4): OK")

# ---- 5. Container download settings -----------------------------------------------------------------------------
/container config set registry-url=https://registry-1.docker.io tmpdir=($mp . "/samm/tmp") layer-dir=($mp . "/samm/layers")
/app settings set disk=$mp
:if ([:len [/ip dns get servers]] = 0 and [:len [/ip dns get dynamic-servers]] = 0) do={
    /ip dns set servers=1.1.1.1,8.8.8.8
    $say "No DNS server was set; using 1.1.1.1 and 8.8.8.8."
}

# ---- 6. The SAMM app --------------------------------------------------------------------------------------------
:if ([:len [/app find where name="samm"]] = 0) do={
    :local url "https://github.com/mhdhaidarah/samm-docker/releases/latest/download/docker-compose.yml"
    :if ([:typeof $SAMMCOMPOSE] = "str" and [:len $SAMMCOMPOSE] > 0) do={ :set url $SAMMCOMPOSE }
    :local f ($mp . "/samm/compose.yml")
    $say "Downloading SAMM's compose file..."
    :do { /tool fetch url=$url dst-path=$f } on-error={
        $say "Could not download the compose file. Check the router's Internet and DNS, then paste the link again."
        :error "SAMM: compose download failed"
    }
    :delay 1s
    :local y [/file get $f contents]
    :if ([:typeof [:find $y "services:"]] = "nil") do={
        $say "The compose file did not download correctly. Paste the link again."
        :error "SAMM: bad compose file"
    }
    # A strong database password and bridge token, made on the router and never sent anywhere.
    :local abc "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
    :local pw [:rndstr length=32 from=$abc]
    :local tok [:rndstr length=32 from=$abc]
    :local rep do={
        :local s $1
        :local out ""
        :local i [:find $s $2]
        :while ([:typeof $i] != "nil") do={
            :set out ($out . [:pick $s 0 $i] . $3)
            :set s [:pick $s ($i + [:len $2]) [:len $s]]
            :set i [:find $s $2]
        }
        :return ($out . $s)
    }
    :set y [$rep $y "change-me-strong-random-string" $pw]
    :set y [$rep $y "change-me-random-token" $tok]
    /file remove $f
    /app add yaml=$y use-https=no disabled=no
    $say "SAMM app added and started. The first start downloads about 1 GB and sets up the database: 10-40 minutes."
} else={
    :if ([/app get [find where name="samm"] disabled]) do={
        /app enable [find where name="samm"]
        $say "The SAMM app was switched off; it is on now."
    } else={
        $say "The SAMM app is already installed; checking it."
    }
}

# ---- 7. Wait for the panel --------------------------------------------------------------------------------------
# Never touch the containers while they start (even switching their logging on restarts them).
:local ip ""
:local up false
:local tries 0
:while (!$up and $tries < 240) do={
    :set tries ($tries + 1)
    # The app's containers share one address, held by the app itself (a container has no ip-address).
    :do { :set ip [/app get [find where name="samm"] ip-address] } on-error={}
    :if ([:typeof [:find $ip "/"]] != "nil") do={ :set ip [:pick $ip 0 [:find $ip "/"]] }
    :if ([:len $ip] > 0) do={
        :do {
            :local r [/tool fetch url=("http://" . $ip . ":8000/health") output=user as-value]
            :if ([:typeof [:find ($r->"data") "\"ok\""]] != "nil") do={ :set up true }
        } on-error={}
    }
    :if (!$up) do={
        :local st ""
        :do { :set st [/app get [find where name="samm"] status] } on-error={}
        # A container with a passing health check shows as healthy, not running: count both.
        :local n ([:len [/container find where name~"samm" and running]] + [:len [/container find where name~"samm" and healthy]])
        :local all [:len [/container find where name~"samm"]]
        :if (($tries % 4) = 1) do={ $say ("Starting... " . $n . "/" . $all . " parts running " . $st . " (" . ($tries / 2) . " min)") }
        :delay 30s
    }
}
:local lan ""
:foreach a in=[/ip address find where !dynamic and !disabled] do={
    :if ([:len $lan] = 0) do={ :local x [/ip address get $a address]; :set lan [:pick $x 0 [:find $x "/"]] }
}
:if ($up) do={
    $say "SAMM is running."
    $say ("Panel:  http://" . $lan . ":8000/admin     (first login admin / admin - change it)")
    $say ("Portal: http://" . $lan . ":8000/")
    $say "Point your routers' RADIUS at this router's address (UDP 1812/1813)."
} else={
    $say "SAMM is still starting after 2 hours of waiting here. It keeps going on its own; check App > samm,"
    $say "or paste the link again later to see where it is."
}
