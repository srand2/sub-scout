#!/bin/bash

program_name="OhDNS"
program_version="v1.4.2"
program_description="Very fast & accurate dns resolving and bruteforcing."

CURRENT_DIR=$(pwd)
AMASS_BIN="${CURRENT_DIR}/amass/amass"
SUBFINDER_BIN="${CURRENT_DIR}/subfinder/subfinder"
MASSDNS_BIN="${CURRENT_DIR}/massdns/massdns"
GOWC_BIN="${CURRENT_DIR}/gowc/gowc"
GOTATOR_BIN="${CURRENT_DIR}/gotator/gotator"
PERMUTE_LIST="${CURRENT_DIR}/wordlists/permutation_list.txt"
COL_LOGO='\033[0;36m'
COL_PROGNAME='\033[1;32m'
COL_PROGVERS='\033[0;36m'
COL_PROGDESC='\033[1;37m'
COL_META='\033[1;37m'
COL_MESSAGE='\033[0;36m'
COL_MESSAGE_TEXT='\033[0;37m'
COL_SUCCESS='\033[1;32m'
COL_SUCCESS_TEXT='\033[0;37m'
COL_ERROR='\033[0;31m'
COL_ERROR_TEXT='\033[0;37m'
COL_TEXT='\033[1;37m'
COL_PV='\033[1;30m'
COL_RESET='\033[0m'

help() {
	echo "OhDNS ${program_version}"
	echo "Use gotator, subfinder, amass, and massdns to accurately resolve a large amount of subdomains and extract wildcard domains."
	echo ""
	usage
}

usage() {
	echo "Usage:"
	echo ""
	echo "	Example:"
	echo "		ohdns [args] [--skip-wildcard-check] [--help] -wl wordlists/small_wordlist.txt -d domain.com"
	echo "		ohdns -wl wordlists/small_wordlist.txt -d domain.com -w output.txt -gt"
	echo ""
	echo "	Optional:"
	echo ""
	echo "		-d, --domain <domain>	Target to scan"
	echo "		-wl, --wordlist	<filename>	Wordlist to do bruteforce"
	echo "		-sc, --subfinder-config	<filename>	SubFinder config file"
	echo "		-ac, --amass-config	<filename>	Amass config file"
	echo "		-i, --ips	Show ips in output"
	echo "		-gt, --gotator	Use gotator to create & bruteforce permutation list"
	echo "		-mg, --max-gotator	Max generated gotator permutations list (Default: 10mil lines)"
	echo "		-sw, --skip-wildcard-check		Do no perform wildcard detection and filtering"
	echo ""
	echo "		-w,  --write <filename>			Write valid domains to a file"
	echo ""
	echo "		-h, --help				Display this message"
}

print_header() {
	printf "${COL_LOGO}" >&2
	printf "

 ██████╗ ██╗  ██╗██████╗ ███╗   ██╗███████╗
██╔═══██╗██║  ██║██╔══██╗████╗  ██║██╔════╝
██║   ██║███████║██║  ██║██╔██╗ ██║███████╗
██║   ██║██╔══██║██║  ██║██║╚██╗██║╚════██║
╚██████╔╝██║  ██║██████╔╝██║ ╚████║███████║
 ╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═══╝╚══════╝
"
	printf "				${COL_PROGNAME}${program_name} ${COL_PROGVERS}${program_version}\n" >&2
	printf '\n' >&2
	printf "${COL_PROGDESC}${program_description}\n" >&2
	printf "${COL_RESET}\n" >&2
}

log_message() {
	printf "${COL_META}[${COL_MESSAGE}*${COL_META}] ${COL_MESSAGE_TEXT}$1${COL_RESET}\n" >&2
}

log_success() {
	printf "${COL_META}[${COL_SUCCESS}!${COL_META}] ${COL_SUCCESS_TEXT}$1${COL_RESET}\n" >&2
}

log_error() {
	printf "${COL_META}[${COL_ERROR}X${COL_META}] ${COL_ERROR_TEXT}$1${COL_RESET}\n" >&2
}

domain_count() {
	local working_domains_list=$1
	local working_domains_list_ip=$2

	if [[ $ips -eq 1 ]]; then
		echo "$(cat "${working_domains_list_ip}" | wc -l)" 2>/dev/null
	else
		echo "$(cat "${working_domains_list}" | wc -l)" 2>/dev/null
	fi

}

wildcard_count() {
	echo "$(cat "${wildcards_work}" | wc -l)" 2>/dev/null
}

parse_args() {

	resolvers_file="$(dirname $0)/resolvers.txt"
	resolvers_trusted_file="$(dirname $0)/trusted.txt"

	limit_rate=0
	limit_rate_trusted=0

	skip_validation=0
	skip_wildcard_check=0
	skip_sanitize=0

	domains_file=''
	amass_config=''
	subfinder_config=''
	ips=0
	gotatorflag=0
	max_gotator=10000000

	resolvers_trusted_file="${CURRENT_DIR}/trusted.txt"
	resolvers_file="${CURRENT_DIR}/trusted.txt"
	skip_validation=1
	mode=1

	set +u
	while :; do
		case $1 in
		--domain | -d)
			domain=$2
			shift
			;;
		--wordlist | -wl)
			wordlist_file=$2
			shift
			;;
		--amass-config | -ac)
			amass_config=$2
			shift
			;;
		--subfinder-config | -sc)
			subfinder_config=$2
			shift
			;;
		--ips | -i)
			ips=1
			;;
		--gotator | -gt)
			gotatorflag=1
			;;
		--max-gotator | -mg)
			max_gotator=$2
			shift
			;;
		--skip-wildcard-check | -sw)
			skip_wildcard_check=1
			;;
		--write | -w)
			domains_file=$2
			shift
			;;
		--help | -h)
			help
			exit 0
			;;
		"")
			break
			;;
		*)
			usage
			echo ""
			echo "Error: unknown argument: $1"
			exit 1
			;;
		esac
		shift
	done

	if [[ -z "${mode}" ]]; then
		usage
		echo ""
		echo "Error: no command given"
		exit 1
	fi

	if [[ ! -f "${resolvers_file}" ]]; then
		echo "Error: unable to open resolvers file ${resolvers_file}"
		echo ""
		exit 1
	fi

	if [[ ! -z "${amass_config}" ]]; then
		if [[ ! -f "${amass_config}" ]]; then
			echo ""
			echo "Error: Cannot open Amass-config file"
			exit 1
		fi
	fi

	if [[ ! -z "${subfinder_config}" ]]; then
		if [[ ! -f "${subfinder_config}" ]]; then
			echo ""
			echo "Error: Cannot open Subfinder-config file"
			exit 1
		fi
	fi

	if [[ "${mode}" -eq 1 ]]; then
		if [[ -z "${wordlist_file}" ]]; then
			usage
			echo ""
			echo "Error: no wordlist specified"
			exit 1
		fi

		if [[ ! -f "${wordlist_file}" ]]; then
			echo "Error: unable to open wordlist file ${wordlist_file}"
			echo ""
			exit 1
		fi

		if [[ -z "${domain}" ]]; then
			usage
			echo ""
			echo "Error: no domain specified"
			exit 1
		fi
	fi

	set -u
}

check_requirements() {
	# massdns
	"${MASSDNS_BIN}" --help >/dev/null 2>&1
	if [[ ! $? -eq 0 ]]; then
		echo "Error: unable to execute massdns."
		echo ""
		exit 1
	fi
}

init() {
	tempdir="$(mktemp -d -t ohdns.XXXXXXXX)"
	log_success "Tempdir: ${tempdir}"
	domains_work="${tempdir}/domains.txt"
	massdns_work="${tempdir}/massdns.txt"
	gowc_work="${tempdir}/gowc.txt"
	tempfile_work="${tempdir}/tempfile.txt"
	domains_withip="${tempdir}/domains_withip.txt"

	gt_domains_work="${tempdir}/gtdomains.txt"
	gt_massdns_work="${tempdir}/gtmassdns.txt"
	gt_domains_withip="${tempdir}/gtdomains_withip.txt"

}

ohdns_check_update() {
	gitremote="$(git ls-remote origin -h refs/heads/master | cut -f1)"
	gitlocal="$(git log --pretty=%H ...refs/heads/master^)"
	if [[ ! "$gitremote" == "$gitlocal" ]]; then
		log_error "NEW VERSION IS AVAILABLE! Use \`git pull\` to update."
		echo ""
	fi
}

prepare_domains_list() {
	log_message "Preparing list of domains for massdns..."
	if [[ "${mode}" -eq 1 ]]; then
		sed -E "s/^(.*)$/\\1.${domain}/" "${OUTPUT_TO_BE_RESOLVED}" >"${domains_work}"
	fi

	if [[ "${skip_sanitize}" -eq 0 ]]; then
		log_message "Sanitizing list..."

		# Set all to lowercase
		cat "${domains_work}" | tr '[:upper:]' '[:lower:]' >"${tempfile_work}"
		cp "${tempfile_work}" "${domains_work}"

		# Keep only valid characters
		cat "${domains_work}" | grep -o '^[a-z0-9\.\-]*$' >"${tempfile_work}"
		cp "${tempfile_work}" "${domains_work}"
	fi
	counted=$(cat "${domains_work}" | wc -l)
	log_success "${counted} domains to resolve with massdns"
}

massdns_trusted() {
	local dfile=$1
	local doutputfile=$2
	local massdns_outputfile=$3

	invoke_massdns "${dfile}" "${resolvers_trusted_file}" "${doutputfile}" "${massdns_outputfile}"
}

invoke_massdns() {
	local dfile=$1
	local resolvers=$2
	local doutputfile=$3
	local massdns_outputfile=$4

	local count="$(cat "${dfile}" | wc -l)"

	"${MASSDNS_BIN}" -q -r "${resolvers}" -o S -t A -s 20000 --processes 2 -w "${massdns_outputfile}" "${dfile}" >/dev/null 2>&1
	cat "${massdns_outputfile}0" "${massdns_outputfile}1" | awk -F '. ' '{ print $1 }' | sort -u >"${doutputfile}"

}

invoke_subfinder() {
	log_message "[SubFinder] Running ..."
	start=$(date +%s)
	if [[ ! -z "${subfinder_config}" ]]; then
		"${SUBFINDER_BIN}" -d ${domain} -all -o "${tempdir}/subfinder_output.txt" -config ${subfinder_config} >/dev/null 2>&1
	else
		"${SUBFINDER_BIN}" -d ${domain} -all -o "${tempdir}/subfinder_output.txt" >/dev/null 2>&1
	fi
	end=$(date +%s)
	runtime=$((end - start))
	local getlines="$(cat "${tempdir}/subfinder_output.txt" | wc -l)"
	log_success "[SubFinder] Finished | Duration: ${runtime}s | Subdomains: ${getlines}"
}

invoke_amass() {
	log_message "[Amass] Running ..."
	start=$(date +%s)
	if [[ ! -z "${amass_config}" ]]; then
		"${AMASS_BIN}" enum --passive -nolocaldb -norecursive -noalts -d ${domain} -o "${tempdir}/amass_output.txt" -config ${amass_config} -timeout 8 -exclude "URLScan" >/dev/null 2>&1
	else
		"${AMASS_BIN}" enum --passive -nolocaldb -norecursive -noalts -d ${domain} -o "${tempdir}/amass_output.txt" -timeout 8 -exclude "URLScan" >/dev/null 2>&1
	fi
	# echo "" > "${tempdir}/amass_output.txt"
	end=$(date +%s)
	runtime=$((end - start))
	local getlines="$(cat "${tempdir}/amass_output.txt" | wc -l)"
	log_success "[Amass] Finished | Duration: ${runtime}s | Subdomains: ${getlines}"
}

invoke_gotator() {
	local valid_subdomains=$1
	gotator_output="${tempdir}/gotator_output.txt"

	log_message "[Gotator] Permutating subdomains ..."
	cat "${valid_subdomains}" | cut -d' ' -f1 >"${tempdir}/validsubsonly.txt"
	"${GOTATOR_BIN}" -sub "${tempdir}/validsubsonly.txt" -perm ${PERMUTE_LIST} -depth 1 -numbers 3 -mindup -adv -silent | head -${max_gotator} | sort -u >"${gt_domains_work}"

	local getlines="$(cat "${gt_domains_work}" | wc -l)"
	log_success "[Gotator] Finished | Made more ${getlines} subdomains to resolve"
}

merge_wordlist() {
	OUTPUT_TO_BE_RESOLVED="${tempdir}/toberesolved.txt"
	log_message "Merging wordlist ..."
	sed -i "s/\.${domain}$//g" "${tempdir}/subfinder_output.txt"
	sed -i "s/\.${domain}$//g" "${tempdir}/amass_output.txt"
	cat "${tempdir}/subfinder_output.txt" "${tempdir}/amass_output.txt" ${wordlist_file} | sort -u >${OUTPUT_TO_BE_RESOLVED}
}

massdns_resolve() {
	local tmp_massdns_work1="${tempdir}/massdns_tmp1.txt"
	local tmp_massdns_work2="${tempdir}/massdns_tmp2.txt"
	local tmp_massdns_domain_work1="${tempdir}/domain_work_tmp1.txt"
	local tmp_massdns_domain_work2="${tempdir}/domain_work_tmp2.txt"
	local working_domain_list=$1
	local working_massdns_list=$2
	local working_domains_list_ip=$3

	log_message "[MassDNS] Invoking massdns... this can take some time"
	log_message "[MassDNS] Running the 1st time ..."
	start=$(date +%s)
	massdns_trusted "${working_domain_list}" "${tmp_massdns_domain_work1}" "${tmp_massdns_work1}"
	end=$(date +%s)
	runtime=$((end - start))
	log_success "[MassDNS] Finished | Duration: ${runtime}s"

	start=$(date +%s)
	log_message "[MassDNS] Running the 2nd time ..."
	massdns_trusted "${working_domain_list}" "${tmp_massdns_domain_work2}" "${tmp_massdns_work2}"
	end=$(date +%s)
	runtime=$((end - start))
	log_success "[MassDNS] Finished | Duration: ${runtime}s"

	log_message "[MassDNS] Merging output from 2 times."
	cat "${tmp_massdns_work2}0" "${tmp_massdns_work2}1" "${tmp_massdns_work1}0" "${tmp_massdns_work1}1" | sort -u > "${working_massdns_list}"
	cat "${tmp_massdns_domain_work1}" "${tmp_massdns_domain_work2}" | sort -u > "${working_domain_list}"

	if [[ $ips -eq 1 ]]; then
		cat "${working_massdns_list}" | awk '{ group[$1] = (group[$1] == "" ? $3 : group[$1] OFS $3 ) } END { for (group_name in group) {x=group_name;gsub(/\.$/,"",x); print x, "\t","["group[group_name]"]"}}' | sort -u >"${working_domains_list_ip}"
	fi

	local counted=$(domain_count "${working_domain_list}" "${working_domains_list_ip}")
	log_success "[MassDNS] ${counted} domains returned a DNS answer"
}

cleanup_wildcards() {
	local working_domain_list=$1
	local working_massdns_list=$2
	local working_domains_list_ip=$3

	log_message "[GoWC] Cleaning wildcard root subdomains..."
	start=$(date +%s)
	if [[ $ips -eq 1 ]]; then
		"${GOWC_BIN}" -m "${working_massdns_list}" -d ${domain} -o "${working_domains_list_ip}" -i >/dev/null 2>&1
	else
		"${GOWC_BIN}" -m "${working_massdns_list}" -d ${domain} -o "${working_domain_list}" >/dev/null 2>&1
	fi
	end=$(date +%s)
	runtime=$((end - start))
	log_success "[GoWC] Finished | Duration: ${runtime}s"
}

export_to_output() {
	local save_domains_to=$1
	local input_domain_only=$2
	local input_domain_withip=$3

	log_message "Exporting domains to ${save_domains_to}"
	echo "" >&2
	output_file="${input_domain_only}"
	if [[ $ips -eq 1 ]]; then
		output_file="${input_domain_withip}"
	fi

	cp "${output_file}" "${save_domains_to}"

}

write_final_output() {
	local phase1=$1
	local phase2=$2
	final_counted=""
	
	if [[ -n "${domains_file}" ]]; then
		cat "${phase1}" "${phase2}" | sort -u > "${domains_file}"
		final_counted=$(cat ${domains_file} | wc -l)
	else
		echo "" >&2
		cat "${phase1}" "${phase2}" | sort -u
		final_counted=$(cat "${phase1}" "${phase2}" | sort -u | wc -l)
		echo "" >&2
	fi

	
	
}

cleanup() {
	debug=0
	if [[ "${debug}" -eq 1 ]]; then
		echo "" >&2
		echo "Intermediary files are in ${tempdir}" >&2
	else
		rm -rf "${tempdir}"
	fi
}

main() {
	global_start=$(date +%s)
	print_header
	parse_args $@
	check_requirements
	ohdns_check_update
	init

	invoke_subfinder
	invoke_amass


	merge_wordlist
	prepare_domains_list
	massdns_resolve "${domains_work}" "${massdns_work}" "${domains_withip}"
	if [[ "${skip_wildcard_check}" -eq 0 ]]; then
		cleanup_wildcards "${domains_work}" "${massdns_work}" "${domains_withip}"
	fi

	local counted=$(domain_count "${domains_work}" "${domains_withip}")
	log_success "Found ${counted} valid domains!"

	phase1_output="${tempdir}/phase1.txt"
	phase2_output="/dev/null"
	export_to_output "${phase1_output}" "${domains_work}" "${domains_withip}"
	
	# Gotator phase
	if [[ $gotatorflag -eq 1 ]]; then
		phase2_output="${tempdir}/phase2.txt"
		invoke_gotator "${phase1_output}"
		massdns_resolve "${gt_domains_work}" "${gt_massdns_work}" "${gt_domains_withip}"
		if [[ "${skip_wildcard_check}" -eq 0 ]]; then
			cleanup_wildcards "${gt_domains_work}" "${gt_massdns_work}" "${gt_domains_withip}"
		fi
		local counted=$(domain_count "${gt_domains_work}" "${gt_domains_withip}")

		log_success "Found ${counted} domains from permutation!"
		export_to_output "${phase2_output}" "${gt_domains_work}" "${gt_domains_withip}"

	fi

	write_final_output "${phase1_output}" "${phase2_output}"
	
	global_end=$(date +%s)
	global_runtime=$((global_end - global_start))
	global_runtimex=$(printf '%dh%dm%ds\n' $(($global_runtime / 3600)) $(($global_runtime % 3600 / 60)) $(($global_runtime % 60)))
	
	log_success "Total: ${final_counted} valid domains in ${global_runtimex}."
	if [[ -n "${domains_file}" ]]; then
		log_success "Output: ${domains_file}"
	fi
	
	cleanup
}

main $@
