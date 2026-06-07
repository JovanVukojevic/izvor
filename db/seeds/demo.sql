-- Demo seed for consultation walkthrough.
-- Two tenants (Intellya, FON), three users each (admin/learner/author), no domain data.
-- All accounts share password 'demo123' (dev-only, dev DB only).
--
-- Idempotent: re-running produces the same end state.
-- Apply as izvor_admin:
--   docker exec -i izvor-postgres psql -U izvor_admin -d izvor < db/seeds/demo.sql

-- Custom GUC carries the hash through both top-level statements and DO blocks
-- (psql \set substitution doesn't reach inside $$-quoted bodies).
SET demo.password_hash = '$2a$10$aH8P2ER.hbSgONDOOtUNNOrO5PF2mXCCHGu.dZqZRB4KTzja2TNr.';

DO $$
DECLARE t_id UUID;
BEGIN
    FOR t_id IN SELECT id FROM system_impl.tenants LOOP
        PERFORM set_config('app.current_tenant', t_id::TEXT, true);
        DELETE FROM impl.lesson_completion;
        DELETE FROM impl.enrollments;
        DELETE FROM impl.lessons;
        DELETE FROM impl.courses;
        DELETE FROM impl.refresh_tokens;
        DELETE FROM impl.categories;
        DELETE FROM impl.users;
        DELETE FROM impl.roles;
    END LOOP;
END $$;

DELETE FROM system_impl.tenants;

SELECT system_api.create_tenant_with_admin('Intellya', 'INTELLYA', 'intellya', 'admin@intellya.com', current_setting('demo.password_hash'));
SELECT system_api.create_tenant_with_admin('FON',      'FON',      'fon',      'admin@fon.com',      current_setting('demo.password_hash'));

DO $$
DECLARE
    rec RECORD;
    v_hash TEXT := current_setting('demo.password_hash');
BEGIN
    FOR rec IN SELECT id, subdomain FROM system_impl.tenants ORDER BY subdomain LOOP
        PERFORM set_config('app.current_tenant', rec.id::TEXT, true);
        PERFORM spec.create_user_internal('jovan@'    || rec.subdomain || '.com', v_hash, 'learner');
        PERFORM spec.create_user_internal('natalija@' || rec.subdomain || '.com', v_hash, 'author');
    END LOOP;
END $$;

-- Catalog content: 4 categories, 4 courses, 11 lessons, 2 enrollments.
-- Hand-rolled fixed UUIDs (a/c/e/f prefixes for category/course/lesson/enrollment)
-- so a reader can grep rows directly from psql output during demos. Idempotency
-- is provided by the DELETE block above (lines 13-27); no ON CONFLICT needed.
-- Lesson markdown is dollar-quoted with $md$ tag so any internal $$ in a code
-- block can't terminate the string early.
DO $$
DECLARE
    v_tenant_id  UUID;
    v_subdomain  TEXT;
    v_author_id  UUID;
    v_learner_id UUID;
BEGIN
    FOR v_tenant_id, v_subdomain IN
        SELECT id, subdomain FROM system_impl.tenants ORDER BY subdomain
    LOOP
        PERFORM set_config('app.current_tenant', v_tenant_id::TEXT, true);

        SELECT id INTO v_author_id  FROM impl.users WHERE email = 'natalija@' || v_subdomain || '.com';
        SELECT id INTO v_learner_id FROM impl.users WHERE email = 'jovan@'    || v_subdomain || '.com';

        IF v_subdomain = 'fon' THEN
            INSERT INTO impl.categories (id, tenant_id, name, description) VALUES
                ('a0000001-0000-0000-0000-000000000000', v_tenant_id, 'Matematika', 'Kursovi iz matematičkih disciplina.'),
                ('a0000002-0000-0000-0000-000000000000', v_tenant_id, 'Menadžment', 'Kursovi iz menadžmenta i organizacije.');

            INSERT INTO impl.courses (id, tenant_id, category_id, author_id, title, description, is_active) VALUES
                ('c0000001-0000-0000-0000-000000000000', v_tenant_id, 'a0000001-0000-0000-0000-000000000000', v_author_id, 'Teorija igara',      'Uvod u matematičku teoriju strateškog odlučivanja.', true),
                ('c0000002-0000-0000-0000-000000000000', v_tenant_id, 'a0000002-0000-0000-0000-000000000000', v_author_id, 'Osnove menadžmenta', 'Osnovni pojmovi menadžmenta i liderstva.',           true);

            INSERT INTO impl.lessons (id, tenant_id, course_id, title, content, position) VALUES
                ('e0000001-0000-0000-0000-000000000000', v_tenant_id, 'c0000001-0000-0000-0000-000000000000', 'Uvod u teoriju igara',
                 $md$## Šta je teorija igara?

Teorija igara je matematička disciplina koja proučava donošenje odluka u situacijama gde ishod svakog učesnika zavisi od izbora svih ostalih. Igrač ne razmišlja samo o tome šta je najbolje za njega — on razmišlja o tome šta će ostali uraditi i kako njegova odluka utiče na njihove.

Klasičan, svima poznat primer je **kamen-papir-makaze**. Tri strategije, tri ishoda, i nijedna strategija nije *dominantna* — ako se zna da protivnik uvek igra kamen, optimalan odgovor je papir; ali tada protivnik najbolje prolazi ako pređe na makaze. Ravnoteža se ne dostiže fiksnim izborom, nego nasumičnom raspodelom.

## Tipične primene

- ekonomija (analiza tržišta sa nekoliko velikih igrača)
- politika (modelovanje koalicija i pregovora)
- vojna strategija (procena protivnikove reakcije)
- biologija (evolucija strategija među jedinkama iste vrste)

U ovom kursu obrađujemo osnovne pojmove i nekoliko klasičnih primera. Cilj nije da naučite da rešite svaku igru, nego da razvijete osećaj za to *kada* strateško razmišljanje menja zaključak.$md$, 1),

                ('e0000002-0000-0000-0000-000000000000', v_tenant_id, 'c0000001-0000-0000-0000-000000000000', 'Nash-ova ravnoteža',
                 $md$## Definicija

Nash-ova ravnoteža je stanje u kome **nijedan igrač nema podsticaj da jednostrano promeni svoju strategiju**, pod pretpostavkom da ostali igrači zadržavaju svoje. To ne znači da je ishod najbolji za sve — samo da nijedan učesnik nema razlog da prvi odstupi.

Pojam je 1950. uveo John Nash, čiji je rad doneo Nobelovu nagradu za ekonomiju 1994.

## Jednostavan 2x2 primer

Dva igrača, svaki bira između strategija A i B. Isplata je oblika *(igrač 1, igrač 2)*:

- oba A → (3, 3)
- oba B → (1, 1)
- 1 igra A, 2 igra B → (0, 4)
- 1 igra B, 2 igra A → (4, 0)

Ovde postoje **dve čiste Nash-ove ravnoteže**: (A, A) i (B, B). U obe nijedan igrač ne dobija ništa ako prvi odstupi sam. Ishod (A, A) je *Pareto-bolji* — svi su bolje prošli — ali bez koordinacije nema garancije da će igrači stići do njega.

Ovaj rascep između *individualne racionalnosti* i *kolektivne efikasnosti* je centralna tema teorije igara.$md$, 2),

                ('e0000003-0000-0000-0000-000000000000', v_tenant_id, 'c0000001-0000-0000-0000-000000000000', 'Zatvorenikova dilema',
                 $md$## Postavka

Dva osumnjičena su uhapšena. Tužilac nema dovoljno dokaza za teže delo, ali nudi svakom pojedinačno isti dogovor: *priznaj, izdaj saučesnika, i izaći ćeš slobodan dok drugi dobija punu kaznu*.

Isplate (godine zatvora, manje je bolje):

- oba ćute → (1, 1)
- oba priznaju → (5, 5)
- 1 ćuti, 2 priznaje → (10, 0)
- 1 priznaje, 2 ćuti → (0, 10)

## Zašto je ovo *dilema*

Sa stanovišta svakog igrača posebno, priznati je *dominantna strategija* — bolje je priznati bez obzira na to šta drugi radi:

- ako drugi ćuti, priznavanjem dobijam 0 umesto 1 → bolje
- ako drugi priznaje, priznavanjem dobijam 5 umesto 10 → bolje

Ravnoteža je dakle (priznaje, priznaje) sa ishodom (5, 5). Ali *zajednički najbolje* je (ćuti, ćuti) sa ishodom (1, 1). Racionalnost svakog pojedinačno vodi do ishoda koji je svima gori.

## Ponovljena igra

Ako se ista situacija ponavlja više puta sa istim učesnicima, dinamika se menja — strategije kao **„odgovori istom merom"** (*tit-for-tat*) mogu da održe saradnju jer kazna za izdaju dolazi u sledećem krugu.$md$, 3),

                ('e0000004-0000-0000-0000-000000000000', v_tenant_id, 'c0000002-0000-0000-0000-000000000000', 'Funkcije menadžmenta',
                 $md$## Četiri klasične funkcije

Menadžment se tradicionalno raščlanjuje na četiri funkcije, prvi put sistematski formulisane u radu Henrija Fayola početkom 20. veka:

- **Planiranje** — definisanje ciljeva i puta do njih. Bez planiranja, ostale funkcije nemaju usmerenje.
- **Organizovanje** — raspoređivanje resursa i odgovornosti. Ko šta radi, ko kome odgovara, koje su zavisnosti.
- **Vođenje** — usmeravanje i motivisanje ljudi. Tehnički dobar plan ne sprovodi se sam.
- **Kontrolisanje** — praćenje rezultata u odnosu na plan i korigovanje odstupanja.

## Kako se uklapaju

Funkcije nisu nezavisne — one se *ciklično prepliću*. Plan postavlja okvir koji se onda organizuje u strukturu; vođenje pokreće tu strukturu u rad; kontrola vraća informaciju koja menja sledeći plan.

U praksi, menadžer ne radi jednu funkciju u jednom trenutku — često u istom razgovoru postavlja cilj (planiranje), dodeljuje ga (organizovanje), motiviše izvršioca (vođenje) i traži termin za izveštaj (kontrolisanje).$md$, 1),

                ('e0000005-0000-0000-0000-000000000000', v_tenant_id, 'c0000002-0000-0000-0000-000000000000', 'Stilovi liderstva',
                 $md$Kurt Lewin je 1939. formulisao podelu na tri stila liderstva. Razlika je u tome *gde* nastaje odluka — kod lidera, u grupi, ili kod izvršilaca.

## Autokratski

Lider sam donosi odluke i prenosi ih timu. Komunikacija je *odozgo nadole*. Pogodan kada je vreme kratko, posledice greške velike, ili tim nema iskustva. Brzo daje pravac, ali ugušuje inicijativu i dugoročno smanjuje motivaciju.

## Demokratski

Odluka se donosi *zajedno sa timom* — lider postavlja okvir i pita za mišljenje pre nego što presudi. Pogodan kada je tim iskusan, problem složen, a posledice greške podnošljive. Daje bolje odluke i veću posvećenost, ali traje duže i može da zapadne u beskonačnu raspravu ako lider ne zna *kada* da presudi.

## Laissez-faire

Lider definiše cilj i prepušta timu kako će ga ostvariti. Pogodan kada su izvršioci visoko stručni i samostalni — istraživanje, dizajn, kreativne profesije. Loš izbor kada tim nije siguran u smer ili kada postoje međuzavisnosti koje neko mora da koordinira.

Dobar menadžer **menja stil prema situaciji**, ne prema svom temperamentu. Stil je alat, ne identitet.$md$, 2),

                ('e0000006-0000-0000-0000-000000000000', v_tenant_id, 'c0000002-0000-0000-0000-000000000000', 'Postavljanje ciljeva (SMART)',
                 $md$## Akronim

SMART je popularan okvir za formulisanje ciljeva. Razvio ga je George Doran 1981. godine. Svako slovo označava jedan kriterijum:

- **S — Specific (konkretno)** — cilj mora da imenuje *šta* tačno
- **M — Measurable (merljivo)** — mora postojati jasan način da se proveri da li je postignut
- **A — Achievable (dostižno)** — realno u datim resursima i vremenu
- **R — Relevant (relevantno)** — povezano sa širim ciljem tima ili organizacije
- **T — Time-bound (vremenski omeđeno)** — sa rokom

## Loš primer

> *„Treba da poboljšamo korisničko iskustvo."*

Ovo nije cilj — ovo je želja. Ne kaže *šta* tačno, *kako* se meri, *do kada*.

## Dobar primer

> *„Smanjiti prosečno vreme učitavanja prve stranice sa 3.2s na 1.8s do kraja drugog kvartala, mereno preko Lighthouse-a u produkciji."*

Konkretno, merljivo, dostižno, relevantno, vremenski omeđeno.

## Granice okvira

SMART je dobar za *taktičke* ciljeve — one koji se mogu jasno opisati unapred. Za istraživačke ciljeve preterana metrička strogost zna da pomeri fokus sa razumevanja na *postizanje broja*.$md$, 3);

            INSERT INTO impl.enrollments (id, tenant_id, course_id, user_id, status) VALUES
                ('f0000001-0000-0000-0000-000000000000', v_tenant_id, 'c0000001-0000-0000-0000-000000000000', v_learner_id, 'active');

        ELSIF v_subdomain = 'intellya' THEN
            INSERT INTO impl.categories (id, tenant_id, name, description) VALUES
                ('a0000003-0000-0000-0000-000000000000', v_tenant_id, 'Onboarding', 'Kursovi za nove zaposlene.'),
                ('a0000004-0000-0000-0000-000000000000', v_tenant_id, 'HR',         'Interna HR pravila i procedure.');

            INSERT INTO impl.courses (id, tenant_id, category_id, author_id, title, description, is_active) VALUES
                ('c0000003-0000-0000-0000-000000000000', v_tenant_id, 'a0000003-0000-0000-0000-000000000000', v_author_id, 'Onboarding za Junior programere', 'Prvi koraci za novog člana razvojnog tima.', true),
                ('c0000004-0000-0000-0000-000000000000', v_tenant_id, 'a0000004-0000-0000-0000-000000000000', v_author_id, 'HR pravila',                      'Osnovna HR pravila i procedure.',            true);

            INSERT INTO impl.lessons (id, tenant_id, course_id, title, content, position) VALUES
                ('e0000007-0000-0000-0000-000000000000', v_tenant_id, 'c0000003-0000-0000-0000-000000000000', 'Dobrodošli u tim',
                 $md$## Dobrodošli

Ova stranica je polazište za sve nove članove tima. Cilj nam je da u prvih nedelju dana budeš u stanju da podigneš lokalno okruženje, otvoriš prvi PR, i razumeš ko je za šta zadužen.

## Ko smo

Tim radi na unutrašnjoj platformi za korporativno učenje. Naši korisnici su *zaposleni u firmama koje koriste platformu* — ne krajnji potrošači. To znači da je naš ritam **manje hitan, više struktuiran** nego što bi bio za konzumentski proizvod, ali svaka greška u produkciji pogađa nečiji radni dan.

## Šta radimo dnevno

- **stand-up** svakog jutra u 9:30, kratko, ne duže od 15 minuta
- **review-i** su asinhroni — niko ne čeka *uživo* da bi nastavio
- **planning** ponedeljkom u 10h, jedna nedelja unapred

## Gde naći

- Tehnička dokumentacija — internal wiki, link u kalendarskoj pozivnici
- Pristupi alatima — Slack kanal *#onboarding*, postavi pitanje
- Tvoj mentor — biće ti dodeljen u prvom danu, on prati napredak prve dve nedelje

Sledeća lekcija prolazi kroz konkretnu postavku dev okruženja.$md$, 1),

                ('e0000008-0000-0000-0000-000000000000', v_tenant_id, 'c0000003-0000-0000-0000-000000000000', 'Postavka dev okruženja',
                 $md$## Šta ti treba

- Git, Node.js 20+, Docker Desktop
- Pristup internom GitLab-u (mentor će ti odobriti članstvo)
- IDE po izboru — većina tima koristi VS Code

## Kloniranje

```
git clone git@gitlab.internal:platform/main.git
cd main
```

Ako je ovo prvi put da koristiš interni GitLab, prvo dodaj svoj SSH ključ kroz GitLab UI (Settings → SSH Keys).

## Zavisnosti

```
npm install
```

Prvi `npm install` traje nekoliko minuta — povlači interni *npm registry* kao mirror, koji je sporiji nego javni pri prvom hitu.

## Pokretanje

Lokalna baza i pomoćni servisi se podižu kroz Docker:

```
docker compose up -d
```

Frontend pokrećeš zasebno:

```
npm run start
```

## Provera

Otvori `http://localhost:4200` u browseru. Trebalo bi da vidiš login ekran. Probaj se ulogovati kao **demo nalog** koji ti je mentor dao u prvom danu.

Ako se ne učitava:

- `docker ps` — proveri da su svi servisi *up*
- `npm run start` log — pogledaj poslednju liniju, najčešća greška je port već zauzet
- *#dev-help* Slack kanal — opiši šta vidiš, neko će reagovati$md$, 2),

                ('e0000009-0000-0000-0000-000000000000', v_tenant_id, 'c0000003-0000-0000-0000-000000000000', 'Code review proces',
                 $md$## Otvaranje PR-a

Kada završiš rad na zadatku:

1. Push-uj granu na remote
2. Otvori PR ka `main`
3. Popuni *opis* — šta menjaš, zašto, kako si testirao
4. Dodaj *reviewere* — najmanje jedan iz tima

Granu ne diraj posle otvaranja PR-a osim kroz dodatne commitove na osnovu komentara. Force-push posle review-a otežava praćenje promena.

## Šta očekujemo u opisu

- **Šta se menja** — jedna do dve rečenice
- **Zašto** — link ka tiketu ili kratko objašnjenje konteksta
- **Kako je testirano** — manuelni koraci ili automatski testovi
- **Šta nije pokriveno** — ako postoji svesno preskočen slučaj, navedi ga

## Šta nije OK

- PR bez opisa
- PR koji menja više nepovezanih stvari odjednom — *teško je review-ovati, lako je propustiti grešku*
- *„Sitno, ne treba review"* — ne postoji *sitno*; svaki commit u `main` ide kroz proces
- Tihe izmene posle approval-a — ako dodaš nešto novo posle review-a, zatraži ponovan pregled

## Ritam

Cilj nam je da svaki PR dobije prvi komentar **u toku istog radnog dana**. Ako čekaš review duže od 24h, ping-uj reviewer-a — propusti se dešavaju.$md$, 3),

                ('e0000010-0000-0000-0000-000000000000', v_tenant_id, 'c0000004-0000-0000-0000-000000000000', 'Radno vreme i godišnji odmor',
                 $md$## Radno vreme

Standardno radno vreme je **40 sati nedeljno**, fleksibilno raspoređeno između 7h i 19h. Osnovna pravila:

- **jezgro radnog vremena**: 10h–15h (svi dostupni za sastanke i sinhrone razgovore)
- pre i posle jezgra: po dogovoru sa timom
- pauza za ručak: nije računata u radno vreme

Rad od kuće je dozvoljen do **3 dana nedeljno** osim ako menadžer ne naloži drugačije za konkretan period.

## Godišnji odmor

Imaš pravo na **25 radnih dana** godišnjeg odmora. Akumuliraju se proporcionalno tokom godine. Neiskorišćeni dani se prenose u sledeću godinu samo do *kraja marta*; posle toga propadaju.

## Procedura

1. Dogovori termin sa **timom** najmanje nedelju dana unapred
2. Dogovori termin sa **menadžerom** — formalno odobrenje
3. Prijavi u HR sistemu sa tačnim datumima
4. Postavi *out-of-office* u kalendaru i Slack statusu

Za odmor duži od **dve nedelje** dogovor mora biti najmanje *mesec dana unapred* — tim treba vremena da preraspodeli posao.

## Praznici

Državni praznici (Republika Srbija) automatski se računaju kao neradni dani i ne ulaze u kvotu godišnjeg odmora.$md$, 1),

                ('e0000011-0000-0000-0000-000000000000', v_tenant_id, 'c0000004-0000-0000-0000-000000000000', 'Sick leave i bolovanje',
                 $md$## Kratko bolovanje (do 3 dana)

Za blagu prehladu, glavobolju ili sličnu neraspoloženost koja te sprečava da radiš jedan ili dva dana:

1. Pošalji poruku **menadžeru** u Slack-u istog jutra
2. Označi status u kalendaru kao *out sick*
3. Ne treba lekarsko opravdanje za bolovanje **do tri uzastopna radna dana**

Ovi dani se računaju kao bolovanje, ne kao godišnji odmor. Limit je *do 5 takvih dana godišnje*; posle toga svako naredno bolovanje zahteva opravdanje.

## Duže bolovanje

Za bolest koja te zadržava **četiri ili više dana**:

- *neophodno je lekarsko opravdanje* — donosi ga lekar opšte prakse
- opravdanje skenirano dostavlja se HR-u u roku od **48h** od povratka na posao
- za bolovanje duže od **30 dana** dokumentaciju preuzima fond zdravstvenog osiguranja, a HR ti šalje uputstvo

## Šta treba HR-u

- ime i prezime
- period bolovanja (datumi od–do)
- skenirano opravdanje (PDF ili JPG)

Za specifične slučajeve (nega člana porodice, hronična oboljenja, porodiljsko) pitanje šalješ direktno HR-u — procedura se razlikuje od standardnog bolovanja.$md$, 2);

            INSERT INTO impl.enrollments (id, tenant_id, course_id, user_id, status) VALUES
                ('f0000002-0000-0000-0000-000000000000', v_tenant_id, 'c0000003-0000-0000-0000-000000000000', v_learner_id, 'active');
        END IF;
    END LOOP;
END $$;

DO $$
DECLARE
    rec RECORD;
    v_user_count       INT := 0;
    v_category_count   INT := 0;
    v_course_count     INT := 0;
    v_lesson_count     INT := 0;
    v_enrollment_count INT := 0;
    v_partial INT;
BEGIN
    FOR rec IN SELECT id FROM system_impl.tenants LOOP
        PERFORM set_config('app.current_tenant', rec.id::TEXT, true);
        SELECT COUNT(*) INTO v_partial FROM impl.users;       v_user_count       := v_user_count       + v_partial;
        SELECT COUNT(*) INTO v_partial FROM impl.categories;  v_category_count   := v_category_count   + v_partial;
        SELECT COUNT(*) INTO v_partial FROM impl.courses;     v_course_count     := v_course_count     + v_partial;
        SELECT COUNT(*) INTO v_partial FROM impl.lessons;     v_lesson_count     := v_lesson_count     + v_partial;
        SELECT COUNT(*) INTO v_partial FROM impl.enrollments; v_enrollment_count := v_enrollment_count + v_partial;
    END LOOP;
    RAISE NOTICE 'tenants=%, users=%, categories=%, courses=%, lessons=%, enrollments=%',
        (SELECT COUNT(*) FROM system_impl.tenants),
        v_user_count, v_category_count, v_course_count, v_lesson_count, v_enrollment_count;
END $$;
