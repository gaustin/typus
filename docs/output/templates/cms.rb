##
# Generate a Rails application with is something like a CMS.
#
#     $ rails new rails-app-cms -m http://core.typuscms.com/templates/cms.rb
#
# What will you get?
#
# - Typus with authentication.
# - A Entry model which is an STI model.
# - CKEditor for all your textarea fields.
#
# Enjoy!

# Add gems to Gemfile
load_template "http://core.typuscms.com/templates/extras/gems.rb"

# Run generators.
load_template "http://core.typuscms.com/templates/extras/cms_models.rb"

# Run typus generators.
rake "db:migrate"
generate "typus"
generate "typus:migration"
rake "db:migrate"

# Load extra templates.
load_template "http://core.typuscms.com/templates/extras/ckeditor.rb"
