// ╔══════════════════════════════════════════════════════════════════╗
// ║  Job questions — asked before booking so the provider understands ║
// ║  the job before quoting. Answers go into the booking summary as   ║
// ║  "Question: Answer" lines (shown to the provider on the job card).║
// ║  Keep in sync with /js/hs-questions.js on the website.            ║
// ╚══════════════════════════════════════════════════════════════════╝

class JobQuestion {
  final String key;
  final String label; // short label used in the summary sent to the provider
  final String q; // question shown to the customer
  final List<String> options;
  final bool multi;
  final bool required;
  const JobQuestion(this.key, this.label, this.q, this.options,
      {this.multi = false, this.required = true});
}

const _property = ['Independent house', 'Apartment / flat', 'Shop / office', 'Building / complex', 'Factory / warehouse'];
const _howLong = ['1 day', '2–3 days', '1 week', '1 month', 'Ongoing (monthly)'];

class JobQuestions {
  static const Map<String, List<JobQuestion>> bySvc = {
    // Sofa / Carpet Cleaning
    'SVC005': [
      JobQuestion('items', 'Items', 'What needs cleaning?', ['Sofa', 'Carpet / rug', 'Mattress', 'Curtains', 'Dining chairs'], multi: true),
      JobQuestion('size', 'Size', 'How big is it?', ['Small (3-seater / 1 carpet)', 'Medium (5-seater)', 'Large (7+ seater / many items)']),
    ],
    // AC
    'SVC007': [
      JobQuestion('need', 'Need', 'What do you need?', ['Visit & quote only', 'Service / cleaning', 'Not cooling / repair', 'Gas refill', 'Installation', 'Uninstallation']),
      JobQuestion('type', 'AC type', 'Which AC?', ['Split', 'Window', 'Cassette / central', 'Not sure']),
      JobQuestion('count', 'No. of ACs', 'How many ACs?', ['1', '2', '3', '4 or more']),
    ],
    // Home Appliance Repair
    'SVC009': [
      JobQuestion('appliance', 'Appliance', 'Which appliance?', ['Washing machine', 'Refrigerator', 'Microwave', 'TV', 'Geyser', 'Chimney', 'Other']),
      JobQuestion('problem', 'Problem', 'What is the problem?', ['Not working at all', 'Noise / leakage', 'Partly working', 'Installation', 'Not sure']),
      JobQuestion('age', 'Age', 'How old is it?', ['Under 2 years', '2–5 years', 'Over 5 years'], required: false),
    ],
    // Water Purifier
    'SVC010': [
      JobQuestion('need', 'Need', 'What do you need?', ['Service / filter change', 'Repair', 'New installation', 'Yearly AMC']),
      JobQuestion('type', 'Type', 'Purifier type?', ['RO', 'UV', 'RO + UV', 'Not sure']),
    ],
    // Plumber
    'SVC011': [
      JobQuestion('work', 'Work', 'What work is needed?', ['Visit & quote only', 'Leak / tap repair', 'Blockage', 'Fitting (tap / basin / toilet)', 'Water tank / motor', 'New pipeline'], multi: true),
      JobQuestion('count', 'Points', 'How many points / items?', ['1', '2–3', '4–6', 'Whole house']),
      JobQuestion('property', 'Property', 'Property type?', _property),
    ],
    // Electrician
    'SVC012': [
      JobQuestion('work', 'Work', 'What work is needed?', ['Visit & quote only', 'Switch / socket repair', 'Fan / light installation', 'Short circuit / fault', 'New wiring', 'Inverter / MCB'], multi: true),
      JobQuestion('count', 'Points', 'How many points / items?', ['1–2', '3–5', '6–10', 'Whole house']),
      JobQuestion('property', 'Property', 'Property type?', _property),
    ],
    // Carpenter
    'SVC013': [
      JobQuestion('work', 'Work', 'What work is needed?', ['Visit & quote only', 'Repair (door / furniture)', 'Furniture assembly', 'New furniture made', 'Lock / handle fitting', 'Modular kitchen / wardrobe']),
      JobQuestion('size', 'Size', 'How much work?', ['1 small item', 'A few items', 'Full room or more']),
    ],
    // Painter
    'SVC014': [
      JobQuestion('area', 'Area', 'Where?', ['Interior', 'Exterior', 'Both']),
      JobQuestion('paint', 'Paint', 'Who buys the paint?', ['Provider brings paint', 'I will buy paint']),
      JobQuestion('walls', 'Walls', 'Wall condition?', ['Good', 'Cracks / damp — needs putty', 'Not sure'], required: false),
    ],
    // CCTV
    'SVC015': [
      JobQuestion('need', 'Need', 'What do you need?', ['Visit & quote only (site survey)', 'Install new CCTV', 'Add more cameras', 'Repair / service existing']),
      JobQuestion('cameras', 'No. of cameras', 'How many cameras?', ['1', '2', '3–4', '5–8', '9–16', 'More than 16', 'Not sure']),
      JobQuestion('property', 'Property', 'Where will it be installed?', _property),
      JobQuestion('supply', 'Equipment', 'Cameras & recorder (DVR/NVR)?', ['Provider supplies everything', 'I already have the cameras', 'Need advice']),
      JobQuestion('type', 'Camera type', 'Camera type?', ['Wired HD', 'Wi-Fi / IP camera', 'Not sure'], required: false),
      JobQuestion('remote', 'Mobile viewing', 'Watch on your phone?', ['Yes', 'No'], required: false),
    ],
    // Solar Panel Cleaning
    'SVC016': [
      JobQuestion('panels', 'Panels', 'How many panels?', ['1–5', '6–10', '11–20', 'More than 20']),
      JobQuestion('access', 'Roof access', 'Roof access?', ['Easy (stairs)', 'Ladder needed', 'Difficult / high roof']),
    ],
    // Mechanic
    'SVC019': [
      JobQuestion('vehicle', 'Vehicle', 'Which vehicle?', ['Car', 'Bike / scooter']),
      JobQuestion('problem', 'Problem', 'What is the problem?', ['Won\'t start', 'Breakdown on road', 'General service', 'Brakes / clutch', 'Battery / electrical', 'Other']),
      JobQuestion('fuel', 'Fuel', 'Fuel type?', ['Petrol', 'Diesel', 'CNG', 'Electric'], required: false),
    ],
    // Pest Control
    'SVC021': [
      JobQuestion('pest', 'Pest', 'Which pests?', ['Cockroaches', 'Termites', 'Bed bugs', 'Rats / mice', 'Mosquitoes', 'General'], multi: true),
      JobQuestion('size', 'Property size', 'Property size?', ['1 BHK', '2 BHK', '3 BHK', '4+ BHK / villa', 'Shop / office']),
    ],
    // Cook
    'SVC022': [
      JobQuestion('meals', 'Meals', 'Which meals?', ['Breakfast', 'Lunch', 'Dinner', 'Party / function'], multi: true),
      JobQuestion('food', 'Food', 'Food type?', ['Veg', 'Non-veg', 'Both']),
      JobQuestion('often', 'How often', 'How often?', ['One time', 'Daily', 'Few days a week']),
    ],
    // Fitness Trainer
    'SVC026': [
      JobQuestion('goal', 'Goal', 'Your goal?', ['Weight loss', 'Muscle gain', 'General fitness', 'Yoga', 'Rehab / senior fitness']),
      JobQuestion('sessions', 'Sessions', 'How many sessions?', ['Single trial', '12 per month', '20+ per month']),
    ],
    // Doctor
    'SVC027': [
      JobQuestion('reason', 'Reason', 'Reason for visit?', ['Fever / cold', 'Elderly check-up', 'Chronic condition follow-up', 'Post-surgery', 'Other']),
      JobQuestion('patient', 'Patient', 'Patient age?', ['Child', 'Adult', 'Senior (60+)']),
    ],
    // Nurse
    'SVC028': [
      JobQuestion('need', 'Need', 'What care is needed?', ['Injection / IV drip', 'Wound dressing', 'Catheter care', 'Elderly care', 'Post-operative care']),
      JobQuestion('duration', 'Duration', 'For how long?', ['Single visit', 'Daily visits', '12-hour shift', '24-hour stay']),
    ],
    // Lab Test
    'SVC029': [
      JobQuestion('tests', 'Tests', 'Which tests?', ['Routine blood test', 'Diabetes', 'Thyroid', 'Full body check-up', 'Urine test', 'As per prescription'], multi: true),
      JobQuestion('people', 'People', 'How many people?', ['1', '2', '3 or more']),
    ],
    // Babysitter
    'SVC030': [
      JobQuestion('kids', 'Children', 'How many children?', ['1', '2', '3 or more']),
      JobQuestion('age', 'Child age', 'Age of the youngest?', ['Under 1 year', '1–3 years', '3–6 years', '6+ years']),
      JobQuestion('hours', 'Hours per day', 'Hours per day?', ['4 hours', '8 hours', '12 hours', '24 hours / live-in']),
      JobQuestion('howlong', 'For how long', 'For how long?', _howLong),
    ],
    // Elderly Care
    'SVC031': [
      JobQuestion('hours', 'Hours per day', 'Hours per day?', ['Day (12 hours)', 'Night (12 hours)', '24 hours / live-in']),
      JobQuestion('mobility', 'Mobility', 'Patient mobility?', ['Walks on their own', 'Needs support', 'Bedridden']),
      JobQuestion('howlong', 'For how long', 'For how long?', _howLong),
    ],
    // Gardener
    'SVC032': [
      JobQuestion('work', 'Work', 'What work?', ['Regular maintenance', 'Lawn mowing', 'Planting', 'New garden setup', 'Tree trimming'], multi: true),
      JobQuestion('area', 'Area', 'Garden size?', ['Balcony / pots', 'Small garden', 'Large garden / lawn']),
      JobQuestion('often', 'How often', 'How often?', ['One time', 'Weekly', 'Monthly']),
    ],
    // Driver
    'SVC033': [
      JobQuestion('hours', 'Duty', 'Duty length?', ['Few hours', 'Full day (8–12 hours)', 'Outstation trip', 'Monthly driver']),
      JobQuestion('howlong', 'For how long', 'For how many days?', ['1 day', '2–3 days', '1 week', '1 month or more']),
    ],
    // Security Guard
    'SVC034': [
      JobQuestion('guards', 'No. of guards', 'How many guards / bouncers?', ['1', '2', '3–5', '6–10', 'More than 10']),
      JobQuestion('shift', 'Shift', 'Hours per shift?', ['8 hours', '12 hours', '24 hours']),
      JobQuestion('timing', 'Timing', 'Day or night?', ['Day', 'Night', 'Day & night']),
      JobQuestion('howlong', 'For how long', 'For how long?', _howLong),
      JobQuestion('place', 'Location', 'Where?', ['Event / function', 'Home', 'Shop / office', 'Apartment / society', 'Construction site', 'Factory / warehouse']),
    ],
    // Anchor / Emcee
    'SVC035': [
      JobQuestion('lang', 'Language', 'Which language should the anchor host in?', ['Telugu', 'Hindi', 'English', 'Tamil', 'Kannada'], multi: true),
      JobQuestion('guests', 'Guests', 'How many guests?', ['Under 100', '100–300', '300–1000', 'More than 1000']),
      JobQuestion('venue', 'Venue', 'Where is the event?', ['Function hall', 'Hotel / resort', 'Home', 'Outdoor / ground', 'College / office', 'Shop / store'], required: false),
    ],
    // Influencer Promotion
    'SVC036': [
      JobQuestion('promote', 'Promoting', 'What do you want to promote?', ['Shop / showroom', 'Restaurant / café', 'Event', 'Product', 'Service / business', 'Other']),
      JobQuestion('visit', 'Visit', 'Should the influencer visit you?', ['Yes — visit my location', 'No — online only']),
      JobQuestion('reach', 'Followers', 'Influencer size you prefer?', ['Any', '10K+ followers', '50K+ followers', '1 lakh+ followers'], required: false),
      JobQuestion('lang', 'Language', 'Content language?', ['Telugu', 'Hindi', 'English', 'Tamil'], multi: true, required: false),
    ],
  };

  static List<JobQuestion> forService(String svcId) => bySvc[svcId] ?? const [];
}
