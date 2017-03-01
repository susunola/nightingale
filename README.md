## Nightingale EDRS Prototype Version 0.1

Nightingale is a prototype electronic death registration system (EDRS), built to both provide basic EDRS capabilities and explore next generation EDRS concepts. This prototype represents a work-in-progress, and is expected to change and grow over time in response to feedback from subject matter experts and users. Nightingale ERDS currently supports the following functionality at various degrees of maturity:

* User roles for funeral directors, medical certifiers, registrars, and administrators
* Death record data entry
* Basic support for configurable, flexible workflows, such as
  * determining who can initiate a death record
  * assignment of in-process death records to other system users
  * token based login for medical certifiers who are infrequent system users
* Support for structured data entry, minimizing opportunities for user error
* Auditing of user actions
* Basic reports on system usage patterns
* Configurable "supplemental questions", allowing ad-hoc support for specific data gathering needs such as collecting information related to specific natural disasters

### Installation and Setup for Development or Testing

Nightingale EDRS is a Ruby on Rails application that uses the PostgreSQL database for data storage.

#### Prerequisites

To work with the application, you will need to install some prerequisites:

* [Ruby](https://www.ruby-lang.org/)

* [Postgres](http://www.postgresql.org/)

Once the prerequisites are available, Nightingale can be installed and demonstration data can be loaded.

#### Setup

* Retrieve the application source code; if the source code is provided as a zip archive

    `unzip nightingale-edrs-0.1.zip`
    `cd edrs`

* Install ruby gem dependencies

    `bundle install`

* Create the database

    `bundle exec rake db:drop db:create db:migrate db:setup RAILS_ENV=development`

* Set up system with demonstration data

    `bundle exec rake edrs:demo:setup`

  * This will create (all with the password "123456"):
    * A funeral director user (fd@test.com)
    * A physician user (doc@test.com)
    * A registrar user (reg@test.com)

* Manage user accounts

  * Create a user

      `bundle exec rake edrs:users:create EMAIL=<email_address> PASS=<password>`
 
  * List all currently registered users (and their roles)

      `bundle exec rake edrs:users:list`
 
  * Delete a user

      `bundle exec rake edrs:users:delete EMAIL=<email_address>`

  * Grant a user admin privileges

      `bundle exec rake edrs:users:grant_admin EMAIL=<email_address>`

  * Revoke admin privileges from a user

      `bundle exec rake edrs:users:revoke_admin EMAIL=<email_address>`

  * Add a role to a user

      `bundle exec rake edrs:users:add_role EMAIL=<email_address> ROLE=<role>`

* Run tests

    `bundle exec rake db:drop db:create db:migrate RAILS_ENV=test` (creates test DB, needed first time only)
    `bundle exec rake test`

* Run the application server

    `bundle exec rails server`

    The server will be running at http://localhost:3000/

## Contact Information

For questions or comments about Nightingale EDRS, please send email to

    `cdc-nvss-feedback-list@lists.mitre.org`

