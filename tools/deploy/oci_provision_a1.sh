#!/usr/bin/env bash
# Idempotently creates ONE Always Free Ampere A1 instance with the OCI CLI. Never deletes or modifies anything, never creates a paid shape.
#
# Required environment (from GitHub Actions secrets/variables; none of them are printed):
#   OCI_COMPARTMENT_ID  OCI_SUBNET_ID  OCI_AVAILABILITY_DOMAIN  OCI_IMAGE_ID (an aarch64 Ubuntu/Oracle Linux image)  SSH_PUBLIC_KEY_FILE
# Optional: INSTANCE_NAME (peepeechess-a1)  A1_OCPUS (2)  A1_MEMORY_GB (12)  BOOT_GB (50)
#
# Always Free limits enforced here BEFORE any create call: total A1 <= 4 OCPUs and <= 24 GB memory, total boot volumes <= 200 GB.
# Exit codes: 0 = exists or created (status in $GITHUB_OUTPUT), 3 = refused (would exceed the free limits), 75 = no A1 capacity right now
# (retry later), anything else = real error.
set -euo pipefail
: "${OCI_COMPARTMENT_ID:?}" "${OCI_SUBNET_ID:?}" "${OCI_AVAILABILITY_DOMAIN:?}" "${OCI_IMAGE_ID:?}" "${SSH_PUBLIC_KEY_FILE:?}"
NAME="${INSTANCE_NAME:-peepeechess-a1}"
OCPUS="${A1_OCPUS:-2}"
MEM="${A1_MEMORY_GB:-12}"
BOOT="${BOOT_GB:-50}"
SHAPE="VM.Standard.A1.Flex"   # fixed on purpose: this script can only ever create the Always Free Ampere shape
OUT="${GITHUB_OUTPUT:-/dev/null}"

emit() { echo "$1=$2" >> "$OUT"; echo "$1=$2"; }

instances="$(oci compute instance list --compartment-id "$OCI_COMPARTMENT_ID" --all --output json)"

# 1) idempotency: an instance with this name that is not terminated means there is nothing to do
existing="$(jq -r --arg n "$NAME" '[.data[] | select(."display-name"==$n and ."lifecycle-state" != "TERMINATED" and ."lifecycle-state" != "TERMINATING")] | length' <<<"$instances")"
if [ "$existing" != "0" ]; then
  emit status exists
  exit 0
fi

# 2) Always Free arithmetic over everything already using the A1 shape (running, stopped or being created)
used_ocpus="$(jq -r '[.data[] | select(.shape=="VM.Standard.A1.Flex" and ."lifecycle-state" != "TERMINATED" and ."lifecycle-state" != "TERMINATING") | (."shape-config".ocpus // 0)] | add // 0' <<<"$instances")"
used_mem="$(jq -r '[.data[] | select(.shape=="VM.Standard.A1.Flex" and ."lifecycle-state" != "TERMINATED" and ."lifecycle-state" != "TERMINATING") | (."shape-config"."memory-in-gbs" // 0)] | add // 0' <<<"$instances")"
boot_volumes="$(oci bv boot-volume list --compartment-id "$OCI_COMPARTMENT_ID" --availability-domain "$OCI_AVAILABILITY_DOMAIN" --all --output json)"
used_boot="$(jq -r '[.data[] | select(."lifecycle-state" != "TERMINATED" and ."lifecycle-state" != "TERMINATING") | ."size-in-gbs"] | add // 0' <<<"$boot_volumes")"
awk -v u="$used_ocpus" -v r="$OCPUS" 'BEGIN{exit !(u+r<=4)}' || { emit status refused; echo "A1 OCPUs would be $used_ocpus + $OCPUS > 4 (Always Free limit)" >&2; exit 3; }
awk -v u="$used_mem" -v r="$MEM" 'BEGIN{exit !(u+r<=24)}' || { emit status refused; echo "A1 memory would be $used_mem + $MEM > 24 GB (Always Free limit)" >&2; exit 3; }
awk -v u="$used_boot" -v r="$BOOT" 'BEGIN{exit !(u+r<=200)}' || { emit status refused; echo "boot volumes would be $used_boot + $BOOT > 200 GB (Always Free limit)" >&2; exit 3; }

# 3) create (one attempt per run; the hourly workflow is the retry loop)
set +e
result="$(oci compute instance launch \
  --compartment-id "$OCI_COMPARTMENT_ID" \
  --availability-domain "$OCI_AVAILABILITY_DOMAIN" \
  --subnet-id "$OCI_SUBNET_ID" \
  --image-id "$OCI_IMAGE_ID" \
  --shape "$SHAPE" \
  --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEM}" \
  --boot-volume-size-in-gbs "$BOOT" \
  --display-name "$NAME" \
  --assign-public-ip true \
  --ssh-authorized-keys-file "$SSH_PUBLIC_KEY_FILE" \
  --wait-for-state RUNNING --output json 2>&1)"
code=$?
set -e
if [ "$code" -ne 0 ]; then
  if grep -qiE "out of (host )?capacity|OutOfHostCapacity|Out of capacity" <<<"$result"; then
    emit status no-capacity
    exit 75
  fi
  # print the CLI error (it contains no secrets) so the workflow log explains the failure
  echo "$result" | tail -n 20 >&2
  emit status error
  exit 1
fi
instance_id="$(jq -r '.data.id' <<<"$result")"
vnic="$(oci compute instance list-vnics --instance-id "$instance_id" --output json | jq -r '.data[0]["public-ip"]')"
emit status created
emit instance_id "$instance_id"
emit public_ip "$vnic"
