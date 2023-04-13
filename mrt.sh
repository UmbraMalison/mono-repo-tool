#!/bin/bash

#set -x

wdir="$(pwd)"
monorepo="${wdir}/demo/monorepo"
subrepo="${wdir}/demo/subrepo"
newrepo="${wdir}/demo/newrepo"
deps="${wdir}/deps"

# to group the commits with time, this delay is added between one set of related activities and the next set.
# this simulates related work that should end up in the same commit in the new monorepo.
delay=2
# tolerance for identifying grouped commits based on their consecutive time differences.
# consecutive commits with this or less time between are considered related.
# should be less than the delay! (in seconds).
group_tol=1

repos=( repo1 repo2 repo3 repo4 repo5 repo6 )

# tags lightweight or annotated at random.
function r_tag()
{
	tag="${1}"
	annotation="${2}"

	if (( RANDOM % 2 )); then
		# LIGHTWEIGHT tag
		git tag "${tag}"
	else
		# ANNOTATED TAG
		git tag -a "${tag}" -m "${annotation}"
	fi
}

function abs()
{
	declare -i result=$(( ${1} * ${1} ))
	echo $(echo "sqrt(${result})" | bc)
}


function create_monorepo()
{
	echo
	echo "#####################"
	echo "# Creating MonoRepo #"
	echo "#####################"
	echo

	rm -rf "${monorepo}"
	mkdir -p "${monorepo}"
	cd "${monorepo}"

	git init

	for repo in "${repos[@]}"; do
		mkdir -p "${repo}/src"
		touch "${repo}/src/${repo}.file"
		echo "Initial" > "${repo}/src/${repo}.file"
	done

	git add --all && git commit -m "Initial Commit."
	r_tag "v1" "version 1 - Initial."

	# create distinct timestamps in git commit history.
	sleep ${delay}

	# Represents a shared history of atomically logical commits, applied together.
	changes=( "change 1" "change 2" "change 3" "change 4" "change 5" "change 6" )

	for change in "${changes[@]}"; do
		for repo in "${repos[@]}"; do
			echo "${change}" >> "${repo}/src/${repo}.file"
		done
		git add --all && git commit -m "${change}-group."

		# create distinct timestamps in git commit history
		sleep ${delay}
	done
	r_tag "v2" "version 2 - group wide changes."

	# Represents repo specific commits applied before the split
	mixed_changes=( "repo1:change 7:change 13" "repo2:change 8:change 14" "repo3:change 9:change 15" "repo4:change 10:change 16" "repo5:change 11:change 17" "repo6:change 12:change 18" )

	for changes in "${mixed_changes[@]}"; do
		readarray -d ":" -t changes < <(printf '%s' "${changes}")
		repo="${changes[0]}"
		unset 'changes[0]'
		for change in "${changes[@]}"; do
			echo "${change}" >> "${repo}/src/${repo}.file"
			git add --all && git commit -m "${change}-${repo}."

			# create distinct timestamps in git commit history
			sleep ${delay}
		done
	done

	r_tag "v3" "version 3 - repo specfic changes."
	# monorepo complete.
}


function create_subrepo()
{
	echo
	echo "####################"
	echo "# Creating SubRepo #"
	echo "####################"
	echo

	rm -rf "${subrepo}"
	mkdir -p "${subrepo}"
	cd "${subrepo}"

	for repo in "${repos[@]}"; do
		git clone "${monorepo}" "${repo}"
		(cd "${repo}" && export FILTER_BRANCH_SQUELCH_WARNING=1; git filter-branch --tag-name-filter cat --subdirectory-filter "${repo}")
	done


	# Represents atomically logical commits but split over their respective repos. These should be squashed back together...
	changes=( "change 19" "change 20" "change 21" "change 22" "change 23" "change 24" )

	for change in "${changes[@]}"; do
		for repo in "${repos[@]}"; do
			echo "${change}" >> "${repo}/src/${repo}.file"
			(cd "${repo}" && git add --all && git commit -m "${change}-group.")
		done
		# create distinct timestamps in git commit history
                sleep ${delay}
	done

	for repo in "${repos[@]}"; do
		atag="version 4 - group wide changes applied per repo."
		(cd "${repo}" && git tag v4)
	done

	# Represents repo specific commits applied after the split
	mixed_changes=( "repo1:change 25:change 31" "repo2:change 26:change 32" "repo3:change 27:change 33" "repo4:change 28:change 34" "repo5:change 29:change 35" "repo6:change 30:change 36" )

	for changes in "${mixed_changes[@]}"; do
		readarray -d ":" -t changes < <(printf '%s' "${changes}")
    repo="${changes[0]}"
    unset 'changes[0]'
    for change in "${changes[@]}"; do
      echo "${change}" >> "${repo}/src/${repo}.file"
      (cd "${repo}" && git add --all && git commit -m "${change}-${repo}.")

			# create distinct timestamps in git commit history
			sleep ${delay}
    done
		atag="version 5 - repo specific changes."
		(cd "${repo}" && git tag v5)
	done

	# subrepo complete

}

# This function is about making 'git-filter-repo' available to git
function get_filter-repo()
{
	bin=${HOME}/.local/bin

	if [ ! -f ${bin}/git-filter-repo ]; then

		mkdir -p ${deps}
		(cd  ${deps} && git clone https://github.com/newren/git-filter-repo.git)

		mkdir -p ${bin}
		ln -s ${deps}/git-filter-repo/git-filter-repo ${bin}

	fi

	if [[ ":$PATH:" != *":${bin}:"* ]]; then
		echo "Local bin missing in PATH - User might need to restart session"
		exit
	fi
}

function hraban_rebase()
{
  local repo_name
  local repo_path
  
  repo_name="$(basename $(dirname ${1}))"
  repo_path="${1}"
  echo ""
  echo "##########################################"
  echo "# Rebasing 'tomono': ${repo_name}"
  echo "##########################################"

  cd "${repo_path}"

  rebase_todo_file=".git/rebase-merge/git-rebase-todo"

  # start rebase, and then stop it before it does anything.
  git -c sequence.editor="sed -i '1s/^/b\n/'" rebase --interactive --root

  readarray -t todo < "${rebase_todo_file}"

  # skip the first line because we will compare with previous lines: i=1
  for (( i=1; i<${#todo[@]}; i++ )); do

    prev_line="${todo[i-1]}"
    this_line="${todo[i]}"

    prev_cmd=$(echo "${prev_line}" | awk '{print $1;}')
    this_cmd=$(echo "${this_line}" | awk '{print $1;}')

    case ${prev_cmd} in
      pick|p)
        prev_sha=$(echo ${prev_line} | awk '{print $2;}')
        ;;
      *)
        # label|merge|reset
        continue
        ;;
    esac

    case ${this_cmd} in
      pick|p)
        this_sha=$(echo ${this_line} | awk '{print $2;}')
        ;;
      *)
        # label|merge|reset
        continue
        ;;
    esac

    prev_msg=$(git log --pretty="format:%s" ${prev_sha})
    this_msg=$(git log --pretty="format:%s" ${next_sha})

    if [[ "${prev_msg}" == "${this_msg}" ]]; then
      # fixup
      echo "fixup ${this_sha}"
    fi
  done

  # review
  vim "${rebase_todo_file}"
  cp "${rebase_todo_file}" "./rebase_todo_backup"

  git rebase --continue
}

function hraban()
{
  local repo_subs
  local repo_mono
  local repo_list

  repo_subs="${1}"
  repo_mono="${2}"
  declare -a repo_list

  MONOREPO_NAME="${repo_mono}"
  export MONOREPO_NAME

  if [[ ! -d "${deps}/tomono/.git" ]]; then
    git clone https://github.com/hraban/tomono.git "${deps}/tomono"
  fi

  if [[ -d "${MONOREPO_NAME}" ]]; then
    rm -rvf "${MONOREPO_NAME}"
  fi

  if [[ -f "${repo_mono}.list" ]]; then
    rm -vf "${repo_mono}.list"
  fi

  for sub_path in ${repo_subs}/*; do
    sub_name=$(basename "${sub_path}")
    if [[ ! -d ${sub_path}/.git ]]; then
      # not a git repo
      continue
    fi

    # we have a git repo.
    echo -e "${sub_path}\t${sub_name}" >> "${repo_mono}.list"
  done

  #repo_list=${repo_list%%[[:space:]]}

  echo -e "${repo_list[@]}" | column -t
  cat "${repo_mono}.list" | "${deps}/tomono/tomono"
  
}

function synthetic()
{
  rm -rf "${newrepo}" "${subrepo}"

	get_filter-repo
	create_monorepo
	create_subrepo
  mkdir -p "${newrepo}"
  hraban "${subrepo}" "${newrepo}/monorepo"
  (cd "${newrepo}/monorepo" && git big-picture -o "${wdir}/monorepo1.png" && git log --oneline)
  
  echo "press return to start rebase attempt"
  read

  hraban_rebase "${newrepo}/monorepo"
  (cd "${newrepo}/monorepo" && git big-picture -o "${wdir}monorepo2.png" && git log --oneline)
	#rebase_tags "${newrepo}"
}

echo "Mono Repo Tool"
echo "=============="
echo
PS3="Choose which mode: "
select opt in synthetic; do
	case ${opt} in
		synthetic)
			echo "Synthetic"
			echo "#########"
			echo -e "\nSimulate in a controlled setup, create monorepo, split to sub repo, then convert to mono-repo."
			synthetic
			break
			;;
		*)
			echo "Invalid"
			;;
	esac
done
