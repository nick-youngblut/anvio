# default mode with read recruitment

rule make_metagenomics_config_file:
    """Make a METAGENOMICS WORKFLOW config.json customized for ECOPHYLO_WORKFLOW"""

    version: 1.0
    log: os.path.join(dirs_dict['LOGS_DIR'], "make_metagenomics_config_file.log")
    input:
        rules.make_fasta_txt.output.fasta_txt
    output:
        config = os.path.join("ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW", "metagenomics_config.json")
    threads: M.T('make_metagenomics_config_file')
    run:

        shell('anvi-run-workflow -w metagenomics --get-default-config {output.config}')

        config = open(output.config)
        config_dict = json.load(config)
        config_dict['fasta_txt'] = 'fasta.txt'
        sample_txt_path = M.samples_txt_file
        config_dict['samples_txt'] = sample_txt_path
        config_dict['references_mode'] = True
        config_dict['anvi_run_hmms']['run'] = False
        config_dict["anvi_script_reformat_fasta"]['run'] = False
        config_dict['anvi_run_kegg_kofams']['run'] = False
        config_dict['anvi_run_ncbi_cogs']['run'] = False
        config_dict['anvi_run_scg_taxonomy']['run'] = False
        config_dict['anvi_run_trna_scan']['run'] = False
        config_dict['anvi_run_scg_taxonomy']['run'] = False
        config_dict['iu_filter_quality_minoche']['run'] = False
        config_dict['anvi_profile']['--min-contig-length'] = 0
        config_dict['bowtie']['threads'] = 5
        config_dict['bowtie_build']['threads'] = 5
        config_dict['anvi_gen_contigs_database']['threads'] = 5

        if M.clusterize_metagenomics_workflow == True:
            config_dict['bowtie']['threads'] = 10
            config_dict['anvi_profile']['threads'] = 10
            config_dict['anvi_merge']['threads'] = 10
        else:
            pass

        with open(output.config, "w") as outfile:
            json.dump(config_dict, outfile, indent=4)


rule run_metagenomics_workflow:
    """Run metagenomics workflow to profile HMM_hits"""

    version: 1.0
    log: "00_LOGS/run_metagenomics_workflow.log"
    input:
        config = rules.make_metagenomics_config_file.output.config,
    output:
        done = touch(os.path.join("ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW", "metagenomics_workflow.done"))
    params:
        HPC_string = M.metagenomics_workflow_HPC_string
    threads: M.T('run_metagenomics_workflow')
    run:

        # Convert r1 and r2 to absolute paths
        samples_txt_new_path = os.path.join("ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW/", M.samples_txt_file)
        samples_txt_new = pd.read_csv(M.samples_txt_file, sep='\t', index_col=False)
        samples_txt_new['r1'] = samples_txt_new['r1'].apply(lambda x: os.path.abspath(str(x)))
        samples_txt_new['r2'] = samples_txt_new['r2'].apply(lambda x: os.path.abspath(str(x)))
        samples_txt_new.to_csv(samples_txt_new_path, sep="\t", index=False, header=True)

        shell("mkdir -p METAGENOMICS_WORKFLOW/00_LOGS && touch {log}")

        if M.clusterize_metagenomics_workflow == True:
            shell('cd ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW/ && anvi-run-workflow -w metagenomics -c metagenomics_config.json --additional-params --cluster \'clusterize -j={{rule}} -o={{log}} -n={{threads}} -x\' --cores 200 --resource nodes=200 --latency-wait 100 --keep-going --rerun-incomplete &> {log} && cd -')
        elif M.metagenomics_workflow_HPC_string:
            HPC_string = params.HPC_string
            shell('cd ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW/ && anvi-run-workflow -w metagenomics -c metagenomics_config.json --additional-params --cluster \'{HPC_string}\' --cores 200 --resource nodes=200 --latency-wait 100 --keep-going --rerun-incomplete &> {log} && cd -')
        else:
            shell("cd ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW/ && anvi-run-workflow -w metagenomics -c metagenomics_config.json -A --rerun-incomplete --latency-wait 100 --keep-going && cd -")
        

rule add_default_collection:
    """"""

    version: 1.0
    log: os.path.join(dirs_dict['LOGS_DIR'], "add_default_collection_{HMM}.log")
    input: metagenomics_workflow_done = os.path.join("ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW", "metagenomics_workflow.done")
    params:
        contigsDB = ancient(os.path.join("ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW/03_CONTIGS", "{HMM}.db")),
        profileDB = os.path.join("ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW/06_MERGED", "{HMM}", "PROFILE.db")
    output: touch(os.path.join("ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW", "{HMM}_add_default_collection.done"))
    threads: M.T('add_default_collection')
    run:
        shell('anvi-script-add-default-collection -c {params.contigsDB} -p {params.profileDB}')


rule anvi_summarize:
    """
    Get coverage values for HMM_hits
    """

    version: 1.0
    log: os.path.join(dirs_dict['LOGS_DIR'], "anvi_summarize_{HMM}.log")
    input: 
        done = os.path.join("ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW", "{HMM}_add_default_collection.done")
    params:
        contigsDB = ancient(os.path.join("ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW/03_CONTIGS", "{HMM}-contigs.db")),
        profileDB = os.path.join("ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW/06_MERGED", "{HMM}", "PROFILE.db"),
        output_dir = os.path.join("ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW/07_SUMMARY", "{HMM}")
    output: touch(os.path.join("ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW/07_SUMMARY", "{HMM}_summarize.done"))
    threads: M.T('anvi_summarize')
    run: 
        shell('anvi-summarize -c {params.contigsDB} -p {params.profileDB} -o {params.output_dir} -C DEFAULT --init-gene-coverages --just-do-it;')
        

rule make_anvio_state_file:
    """Make a state file customized for EcoPhylo workflow interactive interface"""

    version: 1.0
    log: os.path.join(dirs_dict['LOGS_DIR'], "make_anvio_state_file_{HMM}.log")
    input:
        num_tree_tips = rules.subset_DNA_reps_with_QCd_AA_reps_for_mapping.output.NT_for_mapping,
        done_scg = rules.anvi_scg_taxonomy.output.done
    params:
        tax_data_final = os.path.join(dirs_dict['MISC_DATA'], "{HMM}_scg_taxonomy_data.tsv"),
        misc_data_final = os.path.join(dirs_dict['MISC_DATA'], "{HMM}_misc.tsv"),
    output:
        state_file = os.path.join("ECOPHYLO_WORKFLOW", "{HMM}_ECOPHYLO_WORKFLOW_state.json")
    threads: M.T('make_anvio_state_file')
    run:

        HMM_source = M.HMM_source_dict[wildcards.HMM]

        # Read in misc data headers for layer_order
        if HMM_source in M.internal_HMM_sources:
            with open(params.tax_data_final) as f:
                lines = f.read()
                first = lines.split('\n', 1)[0]
            scg_taxonomy_layers_list = first.split("\t")

        with open(params.misc_data_final) as f:
            lines = f.read()
            first = lines.split('\n', 1)[0]
        misc_layers_list = first.split("\t")

        state_dict = {}

        # basics
        state_dict['version'] = '3'
        state_dict['tree-type'] = 'phylogram'
        state_dict['current-view'] = 'single'

        # height and width
        # FIXME: It's unclear to me how the interactive interface determines
        # height and width of a tree when the input value is 0. There has to 
        # be some kind of calculation to determine the tree shape in the backend
        # of the interface because even after I export a "default" state file
        # the height and width are still "0". However, if you change the height and width
        # values within the interface to "" the tree will disappear. I need to sort this 
        # out eventually to have a clean way of changing the tree shape to 
        # match the dimensions of the number of SCGs vs metagenomes. 
        # num_tree_tips = pd.read_csv(input.num_tree_tips, \
        #                             sep="\t", \
        #                             index_col=None)


        # layer-orders
        first_layers = ["__parent__", "length", "gc_content"]
        metagenomes = []

        for metagenome in M.sample_names_for_mapping_list:
            metagenomes.append(metagenome)

        if HMM_source in M.internal_HMM_sources:
            layer_order = first_layers + metagenomes + misc_layers_list + scg_taxonomy_layers_list 
        else:
            layer_order = first_layers + metagenomes + misc_layers_list 

        state_dict['layer-order'] = layer_order

        # layers
        layers_dict = {}

        metagenome_layers_dict = {}

        metagenome_attributes = {
            "color": "#000000",
            "height": "180",
            "margin": "15",
            "type": "bar",
            "color-start": "#FFFFFF"
            }

        for metagenome in metagenomes:
            metagenome_layers_dict[str(metagenome)] = metagenome_attributes

        layer_attributes_parent = {
            "color": "#000000",
            "height": "0",
            "margin": "15",
            "type": "color",
            "color-start": "#FFFFFF"
            }

        length = {
            "color": "#000000",
            "height": "0",
            "margin": "15",
            "type": "color",
            "color-start": "#FFFFFF"
            }

        gc_content = {
            "color": "#000000",
            "height": "0",
            "margin": "15",
            "type": "color",
            "color-start": "#FFFFFF"
            }

        identifier = {
            "color": "#000000",
            "height": "0",
            "margin": "15",
            "type": "color",
            "color-start": "#FFFFFF"
            }

        percent_identity = {
            "color": "#000000",
            "height": "180",
            "margin": "15",
            "type": "line",
            "color-start": "#FFFFFF"
            }
            
        layers_dict.update(metagenome_layers_dict)
        layers_dict['__parent__'] = layer_attributes_parent
        layers_dict['length'] = length
        layers_dict['gc_content'] = gc_content
        layers_dict['identifier'] = identifier
        layers_dict['percent_identity'] = percent_identity

        state_dict['layers'] = layers_dict

        # views
        views_dict = {}

        single_dict = {}

        percent_identity = {
            "normalization": "none",
            "min": {
                "value": "90",
                "disabled": "false"
                },
            "max": {
                "value": "100",
                "disabled": "false"
                }
        }

        single_dict['percent_identity'] = percent_identity 
        views_dict['single'] = single_dict
        state_dict['views'] = views_dict

        with open(output.state_file, "w") as outfile:
                json.dump(state_dict, outfile, indent=4)

rule anvi_import_everything_metagenome:
    """
    Import state file, phylogenetic tree, AND misc data to interactive interface

    If samples.txt is NOT provided then we will make an Ad Hoc profileDB for the tree to import misc data
    """

    version: 1.0
    log: os.path.join(dirs_dict['LOGS_DIR'], "anvi_import_state_{HMM}.log")
    input:
        tree = rules.rename_tree_tips.output.tree,
        misc_data = rules.make_misc_data.output.misc_data_final,
        state = rules.make_anvio_state_file.output,
        done = rules.run_metagenomics_workflow.output.done
    params:
        tax_data_final = rules.anvi_scg_taxonomy.params.tax_data_final,
        profileDB = os.path.join("ECOPHYLO_WORKFLOW/METAGENOMICS_WORKFLOW/06_MERGED", "{HMM}", "PROFILE.db"),
        tree_profileDB = os.path.join(dirs_dict['TREES'], "{HMM}", "{HMM}-PROFILE.db")
    output: 
        touch(os.path.join("ECOPHYLO_WORKFLOW", "{HMM}_state_imported.done")),

    threads: M.T('anvi_import_state')
    run:
        state = os.path.join("ECOPHYLO_WORKFLOW", "{wildcards.HMM}_ECOPHYLO_WORKFLOW_state.json")

        shell(f"anvi-import-state -p {params.profileDB} -s {state} -n default")

        shell("anvi-import-items-order -p {params.profileDB} -i {input.tree} --name {wildcards.HMM}_tree")

        shell("anvi-import-misc-data -p {params.profileDB} --target-data-table items {input.misc_data} --just-do-it")

        HMM_source = M.HMM_source_dict[wildcards.HMM]
        
        if HMM_source in M.internal_HMM_sources:
            shell("anvi-import-misc-data -p {params.profileDB} --target-data-table items {params.tax_data_final} --just-do-it")