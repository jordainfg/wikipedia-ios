#!/usr/bin/env ruby

pr_branch = 'twn'
base_branch = 'develop'
title = 'localization'

current_hash = `git ls-remote --heads origin | grep refs/heads/#{pr_branch}`.split.first

if !current_hash || current_hash == ''
  puts "no current hash"
  exit 0
end

current_hash = current_hash.strip

hash_file = "~/PR_#{pr_branch.upcase}_CURRENT_HASH"

previous_hash = `cat #{hash_file}`

if previous_hash
  previous_hash = previous_hash.strip
end

if previous_hash == current_hash
  puts "no changes"
  exit 0
end

puts "#{pr_branch} went from #{previous_hash} to #{current_hash}, opening pr"
  
result = `curl -i -d '{"title":"#{title}","head":"#{pr_branch}","base":"#{base_branch}"}' -H "Authorization: token #{ENV['GITHUB_TWN_ACCESS_TOKEN']}" -H "Content-Type: application/json; charset=utf-8" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/wikimedia/wikipedia-ios/pulls`
puts result

if result.include?('HTTP/1.1 201 Created') || result.include?('A pull request already exists')
  `echo "#{current_hash}" > #{hash_file}`
else
  exit 1
end