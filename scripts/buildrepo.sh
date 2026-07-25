#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SUITE="stable"
COMPONENT="main"

BASE="dists/$SUITE/$COMPONENT"

KEY="998DB701C6D3511BE811FB1E139805E18EB6B32B"

ARCHES=(
    all
    amd64
    i386
    arm64
    armhf
    armel
    riscv64
    ppc64el
    s390x
)


echo "Preparing Debian pool structure..."

mkdir -p pool/main


python3 <<'PY'

import subprocess
import shutil
from pathlib import Path


pool = Path("pool/main")



def package_info(deb):

    out = subprocess.check_output(
        [
            "dpkg-deb",
            "-f",
            str(deb),
            "Package",
            "Version",
            "Architecture"
        ],
        text=True
    )

    info={}

    for line in out.splitlines():
        k,v=line.split(":",1)
        info[k]=v.strip()

    return info



# Find loose packages and move into Debian structure

for deb in list(pool.glob("*.deb")):

    info = package_info(deb)

    name = info["Package"]

    first = name[0].lower()

    destination = (
        pool /
        first /
        name
    )

    destination.mkdir(
        parents=True,
        exist_ok=True
    )

    target = destination / deb.name

    print(
        f"Moving {deb.name} -> {target}"
    )

    shutil.move(
        deb,
        target
    )


PY



echo "Cleaning indexes..."

for arch in "${ARCHES[@]}"; do
    rm -rf "$BASE/binary-$arch"
    mkdir -p "$BASE/binary-$arch"
done



echo "Collecting packages..."


python3 <<'PY'

import subprocess
import shutil
from pathlib import Path


pool=Path("pool/main")


targets={

"all":Path("dists/stable/main/binary-all"),
"amd64":Path("dists/stable/main/binary-amd64"),
"i386":Path("dists/stable/main/binary-i386"),
"arm64":Path("dists/stable/main/binary-arm64"),
"armhf":Path("dists/stable/main/binary-armhf"),
"armel":Path("dists/stable/main/binary-armel"),
"riscv64":Path("dists/stable/main/binary-riscv64"),
"ppc64el":Path("dists/stable/main/binary-ppc64el"),
"s390x":Path("dists/stable/main/binary-s390x"),

}



def info(file):

    out=subprocess.check_output(
        [
            "dpkg-deb",
            "-f",
            str(file),
            "Package",
            "Version",
            "Architecture"
        ],
        text=True
    )

    result={}

    for line in out.splitlines():
        k,v=line.split(":",1)
        result[k]=v.strip()

    return result



packages={}


for deb in pool.rglob("*.deb"):

    data=info(deb)

    key=(
        data["Package"],
        data["Architecture"]
    )


    if key not in packages:

        packages[key]=(data["Version"],deb)

    else:

        old,_=packages[key]

        newer=subprocess.run(
            [
                "dpkg",
                "--compare-versions",
                data["Version"],
                "gt",
                old
            ]
        ).returncode==0

        if newer:
            packages[key]=(data["Version"],deb)



for (name,arch),(version,file) in packages.items():

    if arch not in targets:
        print(
            f"Skipping unsupported architecture {arch}"
        )
        continue


    shutil.copy(
        file,
        targets[arch] / file.name
    )


    print(
        f"Using {name} {version} ({arch})"
    )

PY



echo "Generating package indexes..."


for arch in "${ARCHES[@]}"; do

    dpkg-scanpackages \
        --arch "$arch" \
        "$BASE/binary-$arch" \
        /dev/null \
        > "$BASE/binary-$arch/Packages"


    gzip -kf "$BASE/binary-$arch/Packages"

done



echo "Generating Release..."


cat > dists/stable/release.conf <<EOF
APT::FTPArchive::Release::Origin "ECTHQ";
APT::FTPArchive::Release::Label "ECTHQ";
APT::FTPArchive::Release::Suite "stable";
APT::FTPArchive::Release::Codename "stable";
APT::FTPArchive::Release::Architectures "all amd64 i386 arm64 armhf armel riscv64 ppc64el s390x";
APT::FTPArchive::Release::Components "main";
EOF



apt-ftparchive \
    -c dists/stable/release.conf \
    release \
    dists/stable \
    > dists/stable/Release



echo "Signing repository..."


rm -f \
    dists/stable/InRelease \
    dists/stable/Release.gpg



gpg \
    --default-key "$KEY" \
    --armor \
    --detach-sign \
    --output dists/stable/Release.gpg \
    dists/stable/Release



gpg \
    --default-key "$KEY" \
    --clearsign \
    --output dists/stable/InRelease \
    dists/stable/Release



echo "APT repository built successfully"
