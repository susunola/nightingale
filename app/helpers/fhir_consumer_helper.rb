# Helper module for importing FHIR death records into Nightingale
module FhirConsumerHelper

  # Helper method to get the first and last name of the certifier. This
  # will be used to find the doctor in the system that should own the record
  # once it's been consumed.
  def self.certifier_name(fhir_record)
    consumer = FhirConsumerHelper.certifier(fhir_record.entry[2])
    [consumer['personCompletingCauseOfDeathName.firstName'], consumer['personCompletingCauseOfDeathName.lastName']]
  end

  # Given a FHIR death record, build and return an equivalent Nightingle contents
  # structure (that can be used to create/update the information in a
  # Nightingale death record).
  def self.from_fhir(fhir_record)
    contents = {}

    # TODO: Find a better way to figure out what entry is what

    # Grab decedent and certifier
    contents.merge! FhirConsumerHelper.decedent(fhir_record.entry[1])
    contents.merge! FhirConsumerHelper.certifier(fhir_record.entry[2])

    # Grab potential conditions
    index = 3
    (3..6).each do |c|
      entry = fhir_record.entry[c]
      # Stop checking if we've exhausted the cause of deaths
      break unless entry.resource.text.present? && entry.resource.respond_to?('onsetString')
      index += 1
      contents.merge! FhirConsumerHelper.cause_of_death_condition(entry, c-3)
    end

    # Grab observations
    (index..fhir_record.entry.count-1).each do |o|
      entry = fhir_record.entry[o]
      case entry.resource.code.coding.first.code
      when '81956-5'
        # http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-causeOfDeath-ActualOrPresumedDateOfDeath
        contents.merge! FhirConsumerHelper.actual_or_presumed_date_of_death(entry)
      when '85699-7'
        # http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-causeOfDeath-AutopsyPerformed
        contents.merge! FhirConsumerHelper.autopsy_performed(entry)
      when '69436-4'
        # http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-causeOfDeath-AutopsyResultsAvailable
        contents.merge! FhirConsumerHelper.autopsy_results_available(entry)
      when '80616-6'
        # http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-causeOfDeath-DatePronouncedDead
        contents.merge! FhirConsumerHelper.date_pronounced_dead(entry)
      when '69444-8'
        # http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-causeOfDeath-DeathFromWorkInjury
        contents.merge! FhirConsumerHelper.death_resulted_from_injury_at_work(entry)
      when '69448-9'
        # http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-causeOfDeath-DeathFromTransportInjury
        contents.merge! FhirConsumerHelper.injury_leading_to_death_associated_trans(entry)
      when '11374-6'
        # http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-causeOfDeath-DetailsOfInjury
        contents.merge! FhirConsumerHelper.details_of_injury(entry)
      when '69449-7'
        # http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-causeOfDeath-MannerOfDeath
        contents.merge! FhirConsumerHelper.manner_of_death(entry)
      when '74497-9'
        # http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-causeOfDeath-MedicalExaminerContacted
        contents.merge! FhirConsumerHelper.medical_examiner_or_coroner_contacted(entry)
      when '69442-2'
        # http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-causeOfDeath-TimingOfRecentPregnancyInRelationToDeath
        contents.merge! FhirConsumerHelper.timing_of_pregnancy_in_relation_to_death(entry)
      when '69443-0'
        # http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-causeOfDeath-TobaccoUseContributedToDeath
        contents.merge! FhirConsumerHelper.tobacco_use_contributed_to_death(entry)
      end
    end

    contents
  end


  #############################################################################
  # The below section is for consuming the FHIR death record decedent
  # information that is included in a FHIR death record.
  #############################################################################

  # Returns decedent information in Nightingale form given a FHIR death record.
  def self.decedent(decedent_entry)
    patient = decedent_entry.resource
    decedent = {}

    # NOTE: All of this is pretty much optional; will need to be careful
    # about handling cases where these things are not in the FHIR record.

    # TODO: Should SSN be included here?

    # Handle name
    if patient.name && patient.name.length > 0
      name = patient.name.first
      decedent['decedentName.firstName'] = name.given.first if name.given && name.given.first.present?
      # All subsequent 'given' names will be combined and included as the 'middle name'
      decedent['decedentName.middleName'] = name.given.drop(1).join(' ') if name.given && name.given.drop(1).any? && !name.given.drop(1).join(' ').blank?
      # All 'family' names will be combined and included as the 'last name'
      if name.family.is_a?(Array)
        decedent['decedentName.lastName'] = name.family.join(' ') if name.family && name.family.any?
      else
        decedent['decedentName.lastName'] = name.family
      end
      certifier['decedentName.suffix'] = name.suffix.join(' ') if name.suffix && name.suffix.any? && !name.suffix.join(' ').blank?
    end
    # Handle date of birth
    decedent['dateOfBirth.dateOfBirth'] = patient.birthDate if patient.birthDate.present?
    # Handle date and time of death
    if patient.deceasedDateTime.present?
      dateTime = DateTime.parse(patient.deceasedDateTime)
      decedent['dateOfDeath.dateOfDeath'] = dateTime.strftime('%F')
      decedent['timeOfDeath.timeOfDeath'] = dateTime.strftime('%H:%M')
    end
    # Handle address
    if patient.address.present?
      address = patient.address.first
      decedent['decedentAddress.street'] = address.line.first if address.line && address.line.first.present?
      decedent['decedentAddress.city'] = address.city.strip if address.city.present?
      decedent['decedentAddress.state'] = address.state.strip if address.state.present?
      decedent['decedentAddress.zip'] = address.postalCode.strip if address.postalCode.present?
    end
    # The following are extensions
    patient.extension.each do |extension|
      case extension.url
      when 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-race'
        # Handle race
        codes = []
        extension.valueCodeableConcept&.coding.each do |coding|
          codes << RACE_ETHNICITY_CODES.key(coding.code) if RACE_ETHNICITY_CODES.key(coding.code)
        end
        unless codes.empty?
          decedent['race.race.option'] = 'Known'
          decedent['race.race.specify'] = codes.to_json
        end
      when 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-ethnicity'
        # Handle ethnicity
        ethnicity = extension.valueCodeableConcept&.coding.first.display
        if ethnicity == 'Hispanic or Latino'
          decedent['hispanicOrigin.hispanicOrigin.specify'] = 'Hispanic or Latino'
          decedent['hispanicOrigin.hispanicOrigin'] = 'Yes'
        else
          decedent['hispanicOrigin.hispanicOrigin'] = 'No'
        end
      when 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-birthsex'
        # Handle sex
        sex = if extension.valueCode == 'M'
          'Male'
        elsif extension.valueCode == 'F'
          'Female'
        elsif extension.valueCode == 'U'
          'Unknown'
        end
        decedent['sex.sex'] = sex if sex.present?
      when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-Age-extension'
        # TODO: Don't need?
      when 'http://hl7.org/fhir/StructureDefinition/birthPlace'
        # Handle birth place
        address = extension.valueAddress
        if address
          decedent['placeOfBirth.zip'] = address.postalCode if address.postalCode.present?
          decedent['placeOfBirth.city'] = address.city if address.city.present?
          decedent['placeOfBirth.state'] = address.state if address.state.present?
        end
      when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-ServedInArmedForces-extension'
        served = extension.valueBoolean ? 'Yes' : 'No'
        decedent['armedForcesService.armedForcesService'] = served
      when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-PlaceOfDeath-extension'
        extension.extension.each do |sub_extension|
          case sub_extension.url
          when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/shr-core-Address-extension'
            decedent['locationOfDeath.city'] = sub_extension.valueAddress.city.strip if sub_extension.valueAddress.city.present?
            decedent['locationOfDeath.state'] = sub_extension.valueAddress.state.strip if sub_extension.valueAddress.state.present?
            decedent['locationOfDeath.zip'] = sub_extension.valueAddress.postalCode.strip if sub_extension.valueAddress.postalCode.present?
          when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-FacilityName-extension'
            decedent['locationOfDeath.name'] = sub_extension.valueString
          when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-PlaceOfDeathType-extension'
            decedent['placeOfDeath.placeOfDeath'] = sub_extension.valueCodeableConcept&.coding.first.display
          end
        end
      when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-Disposition-extension'
        extension.extension.each do |sub_extension|
          case sub_extension.url
          when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-DispositionType-extension'
            decedent['methodOfDisposition.methodOfDisposition'] = sub_extension.valueCodeableConcept&.coding.first.display
          when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-DispositionFacility-extension'
            sub_extension.extension.each do |sub_sub_extension|
              case sub_sub_extension.url
              when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-FacilityName-extension'
                decedent['placeOfDisposition.name'] = sub_sub_extension.valueString
              when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/shr-core-Address-extension'
                decedent['placeOfDisposition.city'] = sub_sub_extension.valueAddress.city.strip if sub_sub_extension.valueAddress.city.present?
                decedent['placeOfDisposition.state'] = sub_sub_extension.valueAddress.state.strip if sub_sub_extension.valueAddress.state.present?
                decedent['placeOfDisposition.zip'] = sub_sub_extension.valueAddress.postalCode.strip if sub_sub_extension.valueAddress.postalCode.present?
              end
            end
          when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-FuneralFacility-extension'
            sub_extension.extension.each do |sub_sub_extension|
              case sub_sub_extension.url
              when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-FacilityName-extension'
                decedent['funeralFacility.name'] = sub_sub_extension.valueString
              when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/shr-core-Address-extension'
                decedent['funeralFacility.city'] = sub_sub_extension.valueAddress.city.strip if sub_sub_extension.valueAddress.city.present?
                decedent['funeralFacility.state'] = sub_sub_extension.valueAddress.state.strip if sub_sub_extension.valueAddress.state.present?
                decedent['funeralFacility.zip'] = sub_sub_extension.valueAddress.postalCode.strip if sub_sub_extension.valueAddress.postalCode.present?
              end
            end
          end
        end
      when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-Education-extension'
        decedent['education.education'] = extension.valueCodeableConcept&.coding.first.code
      when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-Occupation-extension'
        extension.extension.each do |sub_extension|
          case sub_extension.url
          when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-Job-extension'
            decedent['usualOccupation.usualOccupation'] = sub_extension.valueString
          when 'http://nightingaleproject.github.io/fhirDeathRecord/StructureDefinition/sdr-decedent-Industry-extension'
            decedent['kindOfBusiness.kindOfBusiness'] = sub_extension.valueString
          end
        end
      when 'http://hl7.org/fhir/StructureDefinition/patient-mothersMaidenName'
        decedent['motherName.lastName'] = extension.valueString
      end
    end

    decedent
  end


  #############################################################################
  # The below section is for consuming the FHIR death certifier information
  # that is included in a FHIR death record.
  #############################################################################

  # Returns certifier information in Nightingale form given a FHIR death record.
  def self.certifier(certifier_entry)
    practitioner = certifier_entry.resource
    certifier = {}

    # Handle name
    if practitioner.name && practitioner.name.length > 0
      name = practitioner.name.first
      certifier['personCompletingCauseOfDeathName.firstName'] = name.given.first if name.given && name.given.first.present?
      # All subsequent 'given' names will be combined and included as the 'middle name'
      certifier['personCompletingCauseOfDeathName.middleName'] = name.given.drop(1).join(' ') if name.given && name.given.drop(1).any? && !name.given.drop(1).join(' ').blank?
      # All 'family' names will be combined and included as the 'last name'
      if name.family.is_a?(Array)
        certifier['personCompletingCauseOfDeathName.lastName'] = name.family.join(' ') if name.family && name.family.any?
      else
        certifier['personCompletingCauseOfDeathName.lastName'] = name.family
      end
      certifier['personCompletingCauseOfDeathName.suffix'] = name.suffix.join(' ') if name.suffix && name.suffix.any? && !name.suffix.join(' ').blank?
    end
    # Handle address
    if practitioner.address.present?
      address = practitioner.address.first
      certifier['personCompletingCauseOfDeathAddress.street'] = address.line.first if address.line && address.line.first.present?
      certifier['personCompletingCauseOfDeathAddress.city'] = address.city.strip if address.city.present?
      certifier['personCompletingCauseOfDeathAddress.state'] = address.state.strip if address.state.present?
      certifier['personCompletingCauseOfDeathAddress.zip'] = address.postalCode.strip if address.postalCode.present?
    end
    # Handle type
    certifier_lookup = {
      '434651000124107': 'Certifying Physician',
      '434641000124105': 'Pronouncing and Certifying Physician',
      '440051000124108': 'Medical Examiner/Coroner'
    }.stringify_keys
    if practitioner.extension && practitioner.extension.any?
      practitioner.extension.each do |extension|
        if extension.url == 'https://github.com/nightingaleproject/fhir-death-record/StructureDefinition/certifier-type'
          certifier['certifierType.certifierType'] = certifier_lookup[extension.valueCoding.code] if certifier_lookup[extension.valueCoding.code]
        end
      end
    end
    # NOTE: Certifier qualification is not used in Nightingale

    certifier
  end


  #############################################################################
  # The below section is for consuming FHIR Conditions (causes of deaths)
  # that are included in a FHIR death record.
  #############################################################################

  # Consume FHIR death record Cause-of-Death-Condition.
  def self.cause_of_death_condition(cod_entry, index)
    cause = cod_entry.resource
    cod = {}
    if index == 0
      cod['cod.immediate'] = cause.text.div if cause.text && cause.text.div.present?
      cod['cod.immediateInt'] = cause.onsetString if cause.onsetString.present?
    else
      cod['cod.under' + index.to_s] = cause.text.div if cause.text && cause.text.div.present?
      cod['cod.under' + index.to_s + 'Int'] = cause.onsetString if cause.onsetString.present?
    end
    cod
  end


  #############################################################################
  # The below section is for consuming the various Observations that are
  # included in a FHIR death record.
  #############################################################################

  # Consume FHIR death record Actual-Or-Presumed-Date-Of-Death.
  def self.actual_or_presumed_date_of_death(entry)
    observation = {}
    dateTime = DateTime.parse(entry.resource.valueDateTime)
    observation['dateOfDeath.dateOfDeath'] = dateTime.strftime('%F')
    #observation['dateOfDeath.dateType'] = 'Actual'
    observation['timeOfDeath.timeOfDeath'] = dateTime.strftime('%H:%M')
    #observation['timeOfDeath.timeType'] = 'Actual'
    observation
  end

  # Consume FHIR death record Autopsy-Performed.
  def self.autopsy_performed(entry)
    observation = {}

    value = if entry.resource.valueBoolean == true
              'Yes'
            elsif entry.resource.valueBoolean == false
              'No'
            end

    observation['autopsyPerformed.autopsyPerformed'] = value
    observation
  end

  # Consume FHIR death record Autopsy-Results-Available.
  def self.autopsy_results_available(entry)
    observation = {}

    value = if entry.resource.valueBoolean == true
              'Yes'
            elsif entry.resource.valueBoolean == false
              'No'
            end

    observation['autopsyAvailableToCompleteCauseOfDeath.autopsyAvailableToCompleteCauseOfDeath'] = value
    observation
  end

  # Consume FHIR death record Date-Pronounced-Dead.
  def self.date_pronounced_dead(entry)
    observation = {}
    dateTime = DateTime.parse(entry.resource.valueDateTime)
    observation['datePronouncedDead.datePronouncedDead'] = dateTime.strftime('%F')
    observation['timePronouncedDead.timePronouncedDead'] = dateTime.strftime('%H:%M')
    observation
  end

  # Consume FHIR death record Death-Resulted-From-Injury-At-Work.
  def self.death_resulted_from_injury_at_work(entry)
    observation = {}

    value = if entry.resource.valueBoolean == true
              'Yes'
            elsif entry.resource.valueBoolean == false
              'No'
            end

    observation['deathResultedFromInjuryAtWork.deathResultedFromInjuryAtWork'] = value
    observation
  end

  # Consume FHIR death record Injury-Leading-To-Death-Associated-Trans.
  def self.injury_leading_to_death_associated_trans(entry)
    observation = {}

    # Convert Nightingale input to the proper FHIR specific output
    # See: https://phinvads.cdc.gov/vads/ViewValueSet.action?id=F148DC82-63C3-40B1-A7D2-D7AD78416D4A
    # OID: 2.16.840.1.114222.4.11.6005
    lookup = {
      'Driver/Operator': '236320001',
      'Passenger': '257500003',
      'Pedestrian': '257518000',
      'Other': 'OTH'
    }

    observation['ifTransInjury.ifTransInjury'] = lookup[entry.resource.valueCodeableConcept.coding.first.code]
    observation
  end

  # Consume FHIR death record Details-Of-Injury.
  def self.details_of_injury(entry)
    observation = {}
    observation['detailsOfInjury.detailsOfInjury'] = entry.resource.valueString
    observation
  end

  # Consume FHIR death record Manner-Of-Death.
  def self.manner_of_death(entry)
    observation = {}

    # Convert FHIR information for use in Nightingale
    # See: https://phinvads.cdc.gov/vads/ViewValueSet.action?id=0D3864B7-5330-410D-BC91-40C1C704BBA4
    # OID: 2.16.840.1.114222.4.11.6002
    lookup = {
      '38605008': 'Natural',
      '7878000': 'Accident',
      '44301001': 'Suicide',
      '27935005': 'Homicide',
      '185973002': 'Pending Investigation',
      '65037004': 'Could not be determined'
    }.stringify_keys

    observation['mannerOfDeath.mannerOfDeath'] = lookup[entry.resource.valueCodeableConcept.coding.first.code]
    observation
  end

  # Consume FHIR death record Medical-Examiner-Or-Coroner-Contacted.
  def self.medical_examiner_or_coroner_contacted(entry)
    observation = {}

    value = if entry.resource.valueBoolean == true
              'Yes'
            elsif entry.resource.valueBoolean == false
              'No'
            end

    observation['meOrCoronerContacted.meOrCoronerContacted'] = value
    observation
  end

  # Consume FHIR death record Timing-Of-Pregnancy-In-Relation-To-Death.
  def self.timing_of_pregnancy_in_relation_to_death(entry)
    observation = {}

    # Convert FHIR information for use in Nightingale
    # See: https://phinvads.cdc.gov/vads/ViewValueSet.action?id=C763809B-A38D-4113-8E28-126620B76C2F
    # OID: 2.16.840.1.114222.4.11.6003
    lookup = {
      'PHC1260': 'Not pregnant within past year',
      'PHC1261': 'Pregnant at time of death',
      'PHC1262': 'Not pregnant, but pregnant within 42 days of death',
      'PHC1263': 'Not pregnant, but pregnant 43 days to 1 year before death',
      'PHC1264': 'Unknown if pregnant within the past year',
      'N/A': 'Not pregnant within past year' # 'not applicable' is not shown in Nightingale, use 'Not pregnant within past year' instead
    }.stringify_keys

    observation['pregnancyStatus.pregnancyStatus'] = lookup[entry.resource.valueCodeableConcept.coding.first.code]
    observation
  end

  # Consume FHIR death record Tobacco-Use-Contributed-To-Death.
  def self.tobacco_use_contributed_to_death(entry)
    observation = {}

    # Convert FHIR information for use in Nightingale
    # See: https://phinvads.cdc.gov/vads/ViewValueSet.action?id=FF7F17AE-3D20-473D-9068-E77A08491242
    # OID: 2.16.840.1.114222.4.11.6004
    lookup = {
      '373066001': 'Yes',
      '373067005': 'No',
      '2931005': 'Probably',
      'UNK': 'Unknown',
      'NASK': 'Unknown' # 'not asked' is not shown in Nightingale, use 'Unkown' instead
    }.stringify_keys

    observation['didTobaccoUseContributeToDeath.didTobaccoUseContributeToDeath'] = lookup[entry.resource.valueCodeableConcept.coding.first.code]
    observation
  end


  #############################################################################
  # Lookup helpers
  #############################################################################

  MARITAL_STATUS = {
    'M' => 'Married',
    'W' => 'Widowed',
    'D' => 'Divorced (but not remarried)',
    'S' => 'Never married',
    'U' => 'Unknown',
  }.stringify_keys

  RACE_ETHNICITY_CODES = {
    'White' => '2106-3',
    'Black or African American' => '2054-5',
    'American Indian or Alaskan Native' => '1002-5',
    'Asian' => '2028-5',
    'Asian Indian' => '2029-7',
    'Chinese' => '2034-7',
    'Filipino' => '2036-2',
    'Japanese' => '2039-6',
    'Korean' => '2040-4',
    'Vietnamese' => '2047-9',
    'Native Hawaiian' => '2079-2',
    'Guamanian' => '2087-5',
    'Chamorro' => '2088-3',
    'Samoan' => '2080-0',
    'Other Pacific Islander' => '2500-7'
  }.stringify_keys

end
